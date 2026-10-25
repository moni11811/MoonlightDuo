//
//  StreamFrameViewController.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/18/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "StreamFrameViewController.h"
#import "MainFrameViewController.h"
#import "VideoDecoderRenderer.h"
#import "StreamManager.h"
#import "ControllerSupport.h"
#import "DataManager.h"
#import "../Stream/AdaptiveViewport.h"
#if !TARGET_OS_TV
#import <UIKit/UIHingeInteraction.h>
#endif

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <limits.h>
#include <math.h>
#include <Limelight.h>

#if TARGET_OS_TV
#import <AVFoundation/AVDisplayCriteria.h>
#import <AVKit/AVDisplayManager.h>
#import <AVKit/UIWindow.h>
#endif

@interface AVDisplayCriteria()
@property(readonly) int videoDynamicRange;
@property(readonly, nonatomic) float refreshRate;
- (id)initWithRefreshRate:(float)arg1 videoDynamicRange:(int)arg2;
@end

@implementation StreamFrameViewController {
    ControllerSupport *_controllerSupport;
    StreamManager *_streamMan;
    TemporarySettings *_settings;
    NSTimer *_inactivityTimer;
    NSTimer *_statsUpdateTimer;
    UITapGestureRecognizer *_menuTapGestureRecognizer;
    UITapGestureRecognizer *_menuDoubleTapGestureRecognizer;
    UITapGestureRecognizer *_playPauseTapGestureRecognizer;
    UITextView *_overlayView;
    UILabel *_stageLabel;
    UILabel *_tipLabel;
    UIActivityIndicatorView *_spinner;
    StreamView *_streamView;
    UIScrollView *_scrollView;
    UIView *_desktopBar;
    UIStackView *_desktopShortcuts;
    UILabel *_viewportNotice;
    UIButton *_layoutButton;
    UIButton *_keyboardButton;
    UIButton *_disconnectButton;
    UIButton *_trackpadSideButton;
    UIView *_gamingRevealZone;
    UIView *_portraitSplitHandle;
    UIView *_landscapeSplitHandle;
    UIView *_controlPanel;
    UIView *_trackpad;
    NSMutableSet<NSNumber *> *_heldDesktopKeys;
    BOOL _streamReady;
    CGSize _desiredViewportPixels;
    CGSize _decodedVideoPixels;
    CGSize _requestedViewportPixels;
    CGSize _hostAppliedPixels;
    NSUInteger _resizeGeneration;
    BOOL _resizeInFlight;
    BOOL _trackpadOnLeft;
    BOOL _gamingMenuVisible;
    NSUInteger _gamingMenuGeneration;
    CGFloat _portraitSplitFraction;
    BOOL _portraitSplitIsManual;
    CGFloat _landscapeVideoFraction;
    BOOL _sceneIsBackgrounded;
    BOOL _backgroundConnectionLost;
    NSInteger _hingeStatus;
    BOOL _didLeaveStream;
    BOOL _userIsInteracting;
    CGSize _keyboardSize;
#if DEBUG && !TARGET_OS_TV
    BOOL _fixtureModeSwitched;
#endif
    
#if !TARGET_OS_TV
    UIScreenEdgePanGestureRecognizer *_exitSwipeRecognizer;
#endif
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
#if DEBUG && !TARGET_OS_TV
    if (!_fixtureModeSwitched && [NSProcessInfo.processInfo.arguments containsObject:@"-MoonlightFixtureModeSwitch"]) {
        _fixtureModeSwitched = YES;
        dispatch_async(dispatch_get_main_queue(), ^{ [self cyclePresentationMode]; });
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"-MoonlightFixtureKeyboard"]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self showDesktopKeyboard]; });
    }
#endif
    
#if !TARGET_OS_TV
    [[self revealViewController] setPrimaryViewController:self];
#endif
}

#if TARGET_OS_TV
- (void)controllerPauseButtonPressed:(id)sender { }
- (void)controllerPauseButtonDoublePressed:(id)sender {
    Log(LOG_I, @"Menu double-pressed -- backing out of stream");
    [self returnToMainFrame];
}
- (void)controllerPlayPauseButtonPressed:(id)sender {
    Log(LOG_I, @"Play/Pause button pressed -- backing out of stream");
    [self returnToMainFrame];
}
#endif


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.navigationController setNavigationBarHidden:YES animated:YES];
    
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    _settings = [[[DataManager alloc] init] getSettings];
    _trackpadOnLeft = [[NSUserDefaults standardUserDefaults] boolForKey:@"LandscapeDesktopTrackpadOnLeft"];
    CGFloat savedSplit = [[NSUserDefaults standardUserDefaults] doubleForKey:@"PortraitDesktopSplitFraction"];
    _portraitSplitIsManual = savedSplit >= 0.35 && savedSplit <= 0.72;
    _portraitSplitFraction = _portraitSplitIsManual ? savedSplit : 0;
    CGFloat savedWideSplit = [[NSUserDefaults standardUserDefaults] doubleForKey:@"LandscapeDesktopVideoFraction"];
    _landscapeVideoFraction = savedWideSplit >= 0.35 && savedWideSplit <= 0.72 ? savedWideSplit : 0.5;
    
    _stageLabel = [[UILabel alloc] init];
    [_stageLabel setUserInteractionEnabled:NO];
    [_stageLabel setText:[NSString stringWithFormat:@"Starting %@...", self.streamConfig.appName]];
    [_stageLabel sizeToFit];
    _stageLabel.textAlignment = NSTextAlignmentCenter;
    _stageLabel.textColor = [UIColor whiteColor];
    _stageLabel.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2);
    
    _spinner = [[UIActivityIndicatorView alloc] init];
    [_spinner setUserInteractionEnabled:NO];
#if TARGET_OS_TV
    [_spinner setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleWhiteLarge];
#else
    [_spinner setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleWhite];
#endif
    [_spinner sizeToFit];
    [_spinner startAnimating];
    _spinner.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2 - _stageLabel.frame.size.height - _spinner.frame.size.height);
    
    _controllerSupport = [[ControllerSupport alloc] initWithConfig:self.streamConfig delegate:self];
    _inactivityTimer = nil;
    
    _streamView = [[StreamView alloc] initWithFrame:self.view.bounds];
    _streamView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_streamView setupStreamView:_controllerSupport interactionDelegate:self config:self.streamConfig];
    
#if TARGET_OS_TV
    if (!_menuTapGestureRecognizer || !_menuDoubleTapGestureRecognizer || !_playPauseTapGestureRecognizer) {
        _menuTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPauseButtonPressed:)];
        _menuTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypeMenu)];

        _playPauseTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPlayPauseButtonPressed:)];
        _playPauseTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypePlayPause)];
        
        _menuDoubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPauseButtonDoublePressed:)];
        _menuDoubleTapGestureRecognizer.numberOfTapsRequired = 2;
        [_menuTapGestureRecognizer requireGestureRecognizerToFail:_menuDoubleTapGestureRecognizer];
        _menuDoubleTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypeMenu)];
    }
    
    [self.view addGestureRecognizer:_menuTapGestureRecognizer];
    [self.view addGestureRecognizer:_menuDoubleTapGestureRecognizer];
    [self.view addGestureRecognizer:_playPauseTapGestureRecognizer];

#else
    _exitSwipeRecognizer = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(edgeSwiped)];
    _exitSwipeRecognizer.edges = UIRectEdgeLeft;
    _exitSwipeRecognizer.delaysTouchesBegan = NO;
    _exitSwipeRecognizer.delaysTouchesEnded = NO;
    
    [self.view addGestureRecognizer:_exitSwipeRecognizer];
    _gamingRevealZone = [[UIView alloc] init];
    _gamingRevealZone.backgroundColor = UIColor.clearColor;
    UIPanGestureRecognizer *reveal = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(revealGamingMenu:)];
    reveal.cancelsTouchesInView = NO;
    reveal.delaysTouchesBegan = NO;
    reveal.delaysTouchesEnded = NO;
    [_gamingRevealZone addGestureRecognizer:reveal];
    [self.view addSubview:_gamingRevealZone];
#endif
    
    _tipLabel = [[UILabel alloc] init];
    [_tipLabel setUserInteractionEnabled:NO];
    
#if TARGET_OS_TV
    [_tipLabel setText:@"Tip: Tap the Play/Pause button on the Apple TV Remote to disconnect from your PC"];
#else
    [_tipLabel setText:self.streamConfig.desktopMode ?
     @"Desktop: Disconnect stops only this stream" :
     @"Tip: Swipe from the left edge to disconnect from your PC"];
#endif
    
    [_tipLabel sizeToFit];
    _tipLabel.textColor = [UIColor whiteColor];
    _tipLabel.textAlignment = NSTextAlignmentCenter;
    _tipLabel.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height * 0.9);
    
#if DEBUG
    BOOL layoutFixture = [NSProcessInfo.processInfo.arguments containsObject:@"-MoonlightLayoutFixture"];
#else
    BOOL layoutFixture = NO;
#endif
    if (!layoutFixture) {
        _streamMan = [[StreamManager alloc] initWithConfig:self.streamConfig
                                                renderView:_streamView
                                       connectionCallbacks:self];
        NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
        [opQueue addOperation:_streamMan];
    }
    
#if TARGET_OS_TV
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidBecomeActive:)
                                                 name: UIApplicationDidBecomeActiveNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidEnterBackground:)
                                                 name: UIApplicationDidEnterBackgroundNotification
                                               object: nil];
#else
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive:)
                                                 name:UISceneWillDeactivateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:)
                                                 name:UISceneDidActivateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidEnterBackground:)
                                                 name:UISceneDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardFrameChanged:)
                                                 name:UIKeyboardWillChangeFrameNotification object:nil];
#endif

#if 0
    // FIXME: This doesn't work reliably on iPad for some reason. Showing and hiding the keyboard
    // several times in a row will not correctly restore the state of the UIScrollView.
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(keyboardWillShow:)
                                                 name: UIKeyboardWillShowNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(keyboardWillHide:)
                                                 name: UIKeyboardWillHideNotification
                                               object: nil];
#endif
    
    // Only enable scroll and zoom in absolute touch mode
    if (_settings.absoluteTouchMode) {
        _scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
        _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
#if !TARGET_OS_TV
        [_scrollView.panGestureRecognizer setMinimumNumberOfTouches:2];
#endif
        [_scrollView setShowsHorizontalScrollIndicator:NO];
        [_scrollView setShowsVerticalScrollIndicator:NO];
        [_scrollView setDelegate:self];
        [_scrollView setMaximumZoomScale:10.0f];
        
        // Add StreamView inside a UIScrollView for absolute mode
        [_scrollView addSubview:_streamView];
        [self.view addSubview:_scrollView];
    }
    else {
        // Add StreamView directly in relative mode
        [self.view addSubview:_streamView];
    }
    
    [self.view addSubview:_stageLabel];
    [self.view addSubview:_spinner];
    [self.view addSubview:_tipLabel];
    if (layoutFixture) {
        _streamView.backgroundColor = [UIColor colorWithRed:0.13 green:0.23 blue:0.34 alpha:1];
        UILabel *fixtureLabel = [[UILabel alloc] initWithFrame:_streamView.bounds];
        fixtureLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        fixtureLabel.text = @"LOCAL LAYOUT FIXTURE\nNO VIDEO OR HOST CONNECTION";
        fixtureLabel.numberOfLines = 2;
        fixtureLabel.textColor = UIColor.whiteColor;
        fixtureLabel.textAlignment = NSTextAlignmentCenter;
        fixtureLabel.userInteractionEnabled = NO;
        [_streamView addSubview:fixtureLabel];
        _stageLabel.hidden = YES;
        _spinner.hidden = YES;
        _tipLabel.hidden = YES;
    }

#if !TARGET_OS_TV
    if (@available(iOS 27.1, *)) {
        __weak typeof(self) weakSelf = self;
        UIHingeInteraction *hinge = [[UIHingeInteraction alloc] initWithUpdateHandler:^(UIHingeInteraction *interaction, UIHingeInteractionUpdate *update) {
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil) return;
            strongSelf->_hingeStatus = update.hinge ? update.hinge.status : UIHingeStatusUnknown;
            [strongSelf.view setNeedsLayout];
        }];
        [self.view addInteraction:hinge];
    }
    {
        // Presentation is independent of the Sunshine app identity. A fold or
        // rotation only reflows controls; it never changes the running session.
        _desktopBar = [[UIView alloc] init];
        _desktopBar.translatesAutoresizingMaskIntoConstraints = YES;
        _desktopBar.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.65];
        _desktopBar.layer.cornerRadius = 12;
        _layoutButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_layoutButton addTarget:self action:@selector(cyclePresentationMode) forControlEvents:UIControlEventTouchUpInside];
        _keyboardButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_keyboardButton setTitle:@"Keyboard" forState:UIControlStateNormal];
        [_keyboardButton addTarget:self action:@selector(showDesktopKeyboard) forControlEvents:UIControlEventTouchUpInside];
        _disconnectButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_disconnectButton setTitle:@"Disconnect" forState:UIControlStateNormal];
        [_disconnectButton addTarget:self action:@selector(confirmDesktopDisconnect) forControlEvents:UIControlEventTouchUpInside];
        _trackpadSideButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_trackpadSideButton addTarget:self action:@selector(toggleLandscapeTrackpadSide) forControlEvents:UIControlEventTouchUpInside];
        UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[_layoutButton, _disconnectButton, _trackpadSideButton, _keyboardButton]];
        actions.translatesAutoresizingMaskIntoConstraints = NO;
        actions.axis = UILayoutConstraintAxisHorizontal;
        actions.distribution = UIStackViewDistributionFillEqually;
        actions.spacing = 4;
        [_desktopBar addSubview:actions];
        [NSLayoutConstraint activateConstraints:@[
            [actions.topAnchor constraintEqualToAnchor:_desktopBar.topAnchor constant:6],
            [actions.bottomAnchor constraintEqualToAnchor:_desktopBar.bottomAnchor constant:-6],
            [actions.leadingAnchor constraintEqualToAnchor:_desktopBar.leadingAnchor constant:12],
            [actions.trailingAnchor constraintEqualToAnchor:_desktopBar.trailingAnchor constant:-12]
        ]];

        _viewportNotice = [[UILabel alloc] init];
        _viewportNotice.text = @"Waiting for a matching host display size.";
        _viewportNotice.textColor = UIColor.whiteColor;
        _viewportNotice.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
        _viewportNotice.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        _viewportNotice.numberOfLines = 0;
        _viewportNotice.textAlignment = NSTextAlignmentCenter;
        _viewportNotice.hidden = YES;
        [self.view addSubview:_viewportNotice];

        _controlPanel = [[UIView alloc] init];
        _controlPanel.backgroundColor = [UIColor colorWithRed:0.055 green:0.063 blue:0.071 alpha:1];
        [_controlPanel addSubview:_desktopBar];
        _trackpad = [[UIView alloc] init];
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(16, 16), YES, 0);
        [[UIColor colorWithRed:0.063 green:0.071 blue:0.082 alpha:1] setFill];
        UIRectFill(CGRectMake(0, 0, 16, 16));
        [[UIColor colorWithWhite:0.32 alpha:1] setFill];
        UIBezierPath *dot = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(7, 7, 2, 2)];
        [dot fill];
        UIImage *trackpadPattern = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        _trackpad.backgroundColor = [UIColor colorWithPatternImage:trackpadPattern];
        _trackpad.layer.cornerRadius = 14;
        _trackpad.layer.masksToBounds = YES;
        UILabel *trackpadLabel = [[UILabel alloc] init];
        trackpadLabel.text = @"Trackpad · tap to click";
        trackpadLabel.textColor = UIColor.lightGrayColor;
        trackpadLabel.textAlignment = NSTextAlignmentCenter;
        trackpadLabel.userInteractionEnabled = NO;
        trackpadLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_trackpad addSubview:trackpadLabel];
        [_trackpad addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveTrackpad:)]];
        [_trackpad addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(clickTrackpad:)]];
        [_controlPanel addSubview:_trackpad];
        [self.view addSubview:_controlPanel];

        _heldDesktopKeys = [NSMutableSet set];
        NSMutableArray<UIButton *> *shortcutButtons = [NSMutableArray array];
        NSArray<NSString *> *labels = @[@"Esc", @"Tab", @"Ctrl", @"Alt", @"Win", @"Shift"];
        for (NSInteger index = 0; index < labels.count; index++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.tag = index;
            [button setTitle:labels[index] forState:UIControlStateNormal];
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
            button.backgroundColor = [UIColor colorWithWhite:0.17 alpha:1];
            button.layer.cornerRadius = 9;
            [button addTarget:self action:@selector(desktopShortcutTapped:) forControlEvents:UIControlEventTouchUpInside];
            [shortcutButtons addObject:button];
        }
        _desktopShortcuts = [[UIStackView alloc] initWithArrangedSubviews:shortcutButtons];
        _desktopShortcuts.axis = UILayoutConstraintAxisHorizontal;
        _desktopShortcuts.distribution = UIStackViewDistributionFillEqually;
        _desktopShortcuts.spacing = 6;
        [_controlPanel addSubview:_desktopShortcuts];
        _portraitSplitHandle = [[UIView alloc] init];
        _portraitSplitHandle.backgroundColor = [UIColor colorWithWhite:0.72 alpha:0.9];
        _portraitSplitHandle.layer.cornerRadius = 4;
        [_portraitSplitHandle addGestureRecognizer:[[UIPanGestureRecognizer alloc]
            initWithTarget:self action:@selector(dragPortraitSplit:)]];
        [self.view addSubview:_portraitSplitHandle];
        _landscapeSplitHandle = [[UIView alloc] init];
        _landscapeSplitHandle.backgroundColor = [UIColor colorWithWhite:0.72 alpha:0.9];
        _landscapeSplitHandle.layer.cornerRadius = 9;
        [_landscapeSplitHandle addGestureRecognizer:[[UIPanGestureRecognizer alloc]
            initWithTarget:self action:@selector(dragLandscapeSplit:)]];
        [self.view addSubview:_landscapeSplitHandle];
    }
#endif
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect safe = self.view.safeAreaLayoutGuide.layoutFrame;
    BOOL keyboardVisible = NO;
#if !TARGET_OS_TV
    if (@available(iOS 15.0, *)) {
        // Keep a usable trackpad between the remote pane and the system
        // keyboard. The keyboard layout guide includes its accessory view.
        CGRect keyboard = self.view.keyboardLayoutGuide.layoutFrame;
        if (keyboard.size.height > 0 && CGRectGetMinY(keyboard) < CGRectGetMaxY(safe)) {
            keyboardVisible = YES;
            // Keep the picture and shortcut rows still. The system keyboard
            // covers the lower trackpad instead of moving the whole layout.
        }
    }
#endif
    CGRect divisionFrame = CGRectNull;
#if !TARGET_OS_TV
    if (@available(iOS 27.1, *)) {
        for (UIViewReservedRegion *region in [self.view reservedRegionsOfKind:[UIViewReservedRegionKind divisionRegionKind]]) {
            if (region.isActive) { divisionFrame = region.frame; break; }
        }
    }
#endif
    BOOL desktopLayout = AVUsesDesktopLayoutWithHinge((AVSize){self.view.bounds.size.width, self.view.bounds.size.height},
        (AVLayoutMode)self.streamConfig.presentationMode, (int)_hingeStatus) ||
        (self.streamConfig.presentationMode == AVLayoutAutomatic && !CGRectIsNull(divisionFrame));
    BOOL verticalDivider = !CGRectIsNull(divisionFrame) && divisionFrame.size.height > divisionFrame.size.width;
    BOOL sideBySide = desktopLayout && (verticalDivider ||
        (CGRectIsNull(divisionFrame) && safe.size.width > safe.size.height));
    BOOL horizontalDivider = desktopLayout && !CGRectIsNull(divisionFrame) && !verticalDivider;
    CGFloat portraitSplitY = horizontalDivider ? CGRectGetMidY(divisionFrame) : 0;
    CGRect viewport = self.view.bounds;
    CGRect controls = CGRectZero;
    if (desktopLayout) {
        AVSize safeSize = {safe.size.width, safe.size.height};
        AVRect remote = CGRectIsNull(divisionFrame) ? AVRemoteViewport(safeSize, 1) :
            AVRemoteViewportWithDivision(safeSize,
                (AVRect){divisionFrame.origin.x - safe.origin.x, divisionFrame.origin.y - safe.origin.y,
                         divisionFrame.size.width, divisionFrame.size.height}, 1);
        if (CGRectIsNull(divisionFrame) && safe.size.height > safe.size.width) {
            // Without a reported fold, the manual divider fixes the upper
            // picture region independently of the previously decoded aspect.
            // The default leaves a wide pane near the fold/middle; it is not
            // driven by the old stream's orientation or frame dimensions.
            CGFloat natural = ((MAX(0, safe.size.width - 16) / 1.6) + 40) / MAX(1, safe.size.height);
            CGFloat fraction = _portraitSplitIsManual ? _portraitSplitFraction :
                MIN(0.55, MAX(0.44, natural));
            portraitSplitY = safe.origin.y + floor(safe.size.height * fraction);
            remote = (AVRect){8, 8, MAX(0, safe.size.width - 16),
                              MAX(0, portraitSplitY - safe.origin.y - 40)};
        }
        viewport = CGRectMake(safe.origin.x + remote.x, safe.origin.y + remote.y,
                              remote.width, remote.height);
        if (!CGRectIsNull(divisionFrame) && divisionFrame.size.height > divisionFrame.size.width) {
            CGFloat start = MAX(safe.origin.x, CGRectGetMaxX(divisionFrame));
            controls = CGRectMake(start, safe.origin.y, MAX(0, CGRectGetMaxX(safe) - start), safe.size.height);
        } else {
            CGFloat start = CGRectIsNull(divisionFrame) ? CGRectGetMaxY(viewport) :
                MAX(safe.origin.y, CGRectGetMaxY(divisionFrame));
            controls = CGRectMake(safe.origin.x, start, safe.size.width,
                                  MAX(0, CGRectGetMaxY(safe) - start));
        }
        if (safe.size.height > safe.size.width && CGRectIsNull(divisionFrame)) {
            controls.origin.y = portraitSplitY + 30;
            controls.size.height = MAX(0, CGRectGetHeight(self.view.bounds) - controls.origin.y);
        }
        if (sideBySide) {
            CGFloat boundary = safe.origin.x + floor(safe.size.width *
                (_trackpadOnLeft ? 1.0 - _landscapeVideoFraction : _landscapeVideoFraction));
            CGFloat leftEnd = verticalDivider ? CGRectGetMinX(divisionFrame) : boundary - 4;
            CGFloat rightStart = verticalDivider ? CGRectGetMaxX(divisionFrame) : boundary + 4;
            CGRect left = CGRectMake(safe.origin.x, safe.origin.y,
                                     MAX(0, leftEnd - safe.origin.x), safe.size.height);
            CGRect right = CGRectMake(rightStart, safe.origin.y,
                                      MAX(0, CGRectGetMaxX(safe) - rightStart), safe.size.height);
            controls = _trackpadOnLeft ? left : right;
            viewport = _trackpadOnLeft ? right : left;
        }
    }
    _controlPanel.hidden = !desktopLayout;
    _desktopShortcuts.hidden = !desktopLayout;
    [_streamView setDesktopControlsHidden:desktopLayout];
    [_keyboardButton setTitle:[_streamView isKeyboardVisible] ? @"Hide Keyboard" : @"Keyboard"
                     forState:UIControlStateNormal];
    _keyboardButton.hidden = !desktopLayout;
    _disconnectButton.hidden = !desktopLayout;
    _trackpadSideButton.hidden = !sideBySide;
    _portraitSplitHandle.hidden = !desktopLayout || sideBySide || horizontalDivider;
    _landscapeSplitHandle.hidden = !sideBySide || verticalDivider;
    if (!_landscapeSplitHandle.hidden) {
        CGFloat boundary = safe.origin.x + floor(safe.size.width *
            (_trackpadOnLeft ? 1.0 - _landscapeVideoFraction : _landscapeVideoFraction));
        _landscapeSplitHandle.frame = CGRectMake(boundary - 9, CGRectGetMidY(safe) - 36, 18, 72);
        [self.view bringSubviewToFront:_landscapeSplitHandle];
    }
    if (!_portraitSplitHandle.hidden) {
        _portraitSplitHandle.frame = CGRectMake(CGRectGetMidX(safe) - 36, portraitSplitY - 37, 72, 18);
        [self.view bringSubviewToFront:_portraitSplitHandle];
    }
    [_trackpadSideButton setTitle:_trackpadOnLeft ? @"Pad: Left" : @"Pad: Right" forState:UIControlStateNormal];
    _desktopBar.hidden = !desktopLayout && !_gamingMenuVisible;
    _gamingRevealZone.hidden = desktopLayout || _gamingMenuVisible;
    // Start below the OS top-edge gesture area. Give a downward swipe enough
    // room to begin without requiring near-perfect aim at an invisible target.
    CGFloat revealWidth = MIN(MAX(0, safe.size.width - 16),
                              MIN(136, MAX(96, safe.size.width * 0.3)));
    _gamingRevealZone.frame = CGRectMake(CGRectGetMaxX(safe) - revealWidth - 8,
                                         safe.origin.y + 12, revealWidth, 96);
    NSString *layoutName = desktopLayout ? @"Desktop" : @"Gaming";
    NSString *choice = self.streamConfig.presentationMode == AVLayoutAutomatic ? @"Auto" : @"Manual";
    [_layoutButton setTitle:[NSString stringWithFormat:@"%@: %@", choice, layoutName] forState:UIControlStateNormal];
    if (desktopLayout) {
        _controlPanel.frame = controls;
        if (sideBySide) {
            if (_desktopBar.superview != _controlPanel) [_controlPanel addSubview:_desktopBar];
            _desktopBar.frame = CGRectMake(8, 8, MAX(0, controls.size.width - 16), 50);
            _desktopShortcuts.frame = CGRectMake(14, 66, MAX(0, controls.size.width - 28), 44);
            _trackpad.frame = CGRectMake(14, 118, MAX(0, controls.size.width - 28),
                                         MAX(0, controls.size.height - 126));
        } else {
            if (_desktopBar.superview != self.view) [self.view addSubview:_desktopBar];
            _desktopBar.frame = CGRectMake(safe.origin.x + 8, portraitSplitY - 25,
                                          MAX(0, safe.size.width - 16), 50);
            _desktopShortcuts.frame = CGRectMake(14, 8, MAX(0, controls.size.width - 28), 44);
            _trackpad.frame = CGRectMake(14, 60, MAX(0, controls.size.width - 28),
                                         MAX(0, controls.size.height - 68));
            [self.view bringSubviewToFront:_desktopBar];
            if (!_portraitSplitHandle.hidden) [self.view bringSubviewToFront:_portraitSplitHandle];
        }
        _trackpad.subviews.firstObject.frame = _trackpad.bounds;
        [self.view bringSubviewToFront:_controlPanel];
        if (!sideBySide) {
            [self.view bringSubviewToFront:_desktopBar];
            if (!_portraitSplitHandle.hidden) [self.view bringSubviewToFront:_portraitSplitHandle];
        } else if (!_landscapeSplitHandle.hidden) {
            [self.view bringSubviewToFront:_landscapeSplitHandle];
        }
    } else {
        if (_desktopBar.superview != self.view) [self.view addSubview:_desktopBar];
        _desktopBar.frame = CGRectMake(CGRectGetMaxX(safe) - MIN(safe.size.width - 16, 170) - 8,
                                      safe.origin.y + 8, MIN(safe.size.width - 16, 170), 50);
        [self.view bringSubviewToFront:_desktopBar];
        if (!_gamingMenuVisible) [self.view bringSubviewToFront:_gamingRevealZone];
    }
    if (self.view.window != nil) {
        AVSize current = AVEncodedSize(viewport.size.width, viewport.size.height, self.view.window.screen.scale);
        if (!keyboardVisible && current.width > 0 && current.height > 0) {
            _desiredViewportPixels = [self advertisedModeForViewport:CGSizeMake(current.width, current.height)];
        }
        // A missing or rejected mode must never leave a permanent wait overlay.
        _viewportNotice.text = @"Changing host display size…";
        _viewportNotice.hidden = keyboardVisible || !_resizeInFlight;
        _viewportNotice.frame = CGRectMake(viewport.origin.x + 8, CGRectGetMaxY(viewport) - 52,
                                          MAX(0, viewport.size.width - 16), 44);
        if (!keyboardVisible && _streamReady && !_sceneIsBackgrounded) {
            [self scheduleLiveResize];
        }
    } else {
        _viewportNotice.hidden = YES;
    }
    if (_scrollView != nil) {
        _scrollView.frame = viewport;
        CGSize size = viewport.size;
        if (!CGSizeEqualToSize(_streamView.bounds.size, size)) {
            _scrollView.zoomScale = 1.0;
            _streamView.frame = CGRectMake(0, 0, size.width, size.height);
            _scrollView.contentSize = size;
        }
    } else {
        _streamView.frame = viewport;
    }
    _stageLabel.center = CGPointMake(CGRectGetMidX(viewport), CGRectGetMidY(viewport));
    _spinner.center = CGPointMake(CGRectGetMidX(viewport), CGRectGetMidY(viewport) - 36);
    _tipLabel.center = CGPointMake(CGRectGetMidX(viewport), CGRectGetMaxY(viewport) - 36);
}

#if !TARGET_OS_TV
- (void)keyboardFrameChanged:(NSNotification *)notification {
    [_keyboardButton setTitle:[_streamView isKeyboardVisible] ? @"Hide Keyboard" : @"Keyboard"
                     forState:UIControlStateNormal];
    [self.view setNeedsLayout];
}
#endif

- (void)cyclePresentationMode {
    [self releaseDesktopModifiers];
    self.streamConfig.presentationMode = (self.streamConfig.presentationMode + 1) % 3;
    _gamingMenuVisible = NO;
    ++_gamingMenuGeneration;
#if DEBUG
    // The layout fixture exercises this production action, but must not leave
    // a presentation preference behind for subsequent normal app launches.
    if (![NSProcessInfo.processInfo.arguments containsObject:@"-MoonlightLayoutFixture"]) {
#endif
    [[NSUserDefaults standardUserDefaults] setInteger:self.streamConfig.presentationMode forKey:@"PresentationOverride"];
#if DEBUG
    }
#endif
    [self.view setNeedsLayout];
}

- (void)toggleLandscapeTrackpadSide {
    _trackpadOnLeft = !_trackpadOnLeft;
    [[NSUserDefaults standardUserDefaults] setBool:_trackpadOnLeft forKey:@"LandscapeDesktopTrackpadOnLeft"];
    [self.view setNeedsLayout];
}

- (void)dragPortraitSplit:(UIPanGestureRecognizer *)pan {
    if (_portraitSplitHandle.hidden) return;
    CGRect safe = self.view.safeAreaLayoutGuide.layoutFrame;
    if (safe.size.height <= 0) return;
    if (pan.state == UIGestureRecognizerStateBegan && !_portraitSplitIsManual) {
        CGFloat natural = ((MAX(0, safe.size.width - 16) / 1.6) + 40) / safe.size.height;
        _portraitSplitFraction = MIN(0.55, MAX(0.44, natural));
        _portraitSplitIsManual = YES;
    }
    if (pan.state == UIGestureRecognizerStateChanged) {
        CGFloat delta = [pan translationInView:self.view].y / safe.size.height;
        _portraitSplitFraction = MIN(0.72, MAX(0.35, _portraitSplitFraction + delta));
        [pan setTranslation:CGPointZero inView:self.view];
        [self.view setNeedsLayout];
    } else if (pan.state == UIGestureRecognizerStateEnded) {
        [[NSUserDefaults standardUserDefaults] setDouble:_portraitSplitFraction
                                                   forKey:@"PortraitDesktopSplitFraction"];
    }
}

- (void)dragLandscapeSplit:(UIPanGestureRecognizer *)pan {
    if (_landscapeSplitHandle.hidden) return;
    CGRect safe = self.view.safeAreaLayoutGuide.layoutFrame;
    if (safe.size.width <= 0) return;
    if (pan.state == UIGestureRecognizerStateChanged) {
        CGFloat delta = [pan translationInView:self.view].x / safe.size.width;
        if (_trackpadOnLeft) delta = -delta;
        _landscapeVideoFraction = MIN(0.72, MAX(0.35, _landscapeVideoFraction + delta));
        [pan setTranslation:CGPointZero inView:self.view];
        [self.view setNeedsLayout];
    } else if (pan.state == UIGestureRecognizerStateEnded) {
        [[NSUserDefaults standardUserDefaults] setDouble:_landscapeVideoFraction
                                                   forKey:@"LandscapeDesktopVideoFraction"];
    }
}

- (void)revealGamingMenu:(UIPanGestureRecognizer *)pan {
    if ((pan.state != UIGestureRecognizerStateBegan && pan.state != UIGestureRecognizerStateChanged) ||
        !_controlPanel.hidden || _gamingMenuVisible) return;
    CGPoint travel = [pan translationInView:self.view];
    if (travel.y < 24 || fabs(travel.x) > travel.y * 0.6) return;
    _gamingMenuVisible = YES;
    NSUInteger generation = ++_gamingMenuGeneration;
    [self.view setNeedsLayout];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation != self->_gamingMenuGeneration || self->_didLeaveStream) return;
        self->_gamingMenuVisible = NO;
        [self.view setNeedsLayout];
    });
}

- (void)desktopShortcutTapped:(UIButton *)button {
    if (!_streamReady) return;
    static const short codes[] = {0x1B, 0x09, 0xA2, 0xA4, 0x5B, 0xA0};
    if (button.tag < 0 || button.tag >= 6) return;
    short code = codes[button.tag];
    NSNumber *key = @(code);
    if (button.tag < 2) {
        LiSendKeyboardEvent(code, KEY_ACTION_DOWN, 0);
        LiSendKeyboardEvent(code, KEY_ACTION_UP, 0);
    } else if ([_heldDesktopKeys containsObject:key]) {
        LiSendKeyboardEvent(code, KEY_ACTION_UP, 0);
        [_heldDesktopKeys removeObject:key];
        button.backgroundColor = [UIColor colorWithWhite:0.17 alpha:1];
    } else {
        LiSendKeyboardEvent(code, KEY_ACTION_DOWN, 0);
        [_heldDesktopKeys addObject:key];
        button.backgroundColor = [UIColor colorWithRed:0.20 green:0.40 blue:0.66 alpha:1];
    }
}

- (void)releaseDesktopModifiers {
    if (_streamReady) {
        for (NSNumber *key in _heldDesktopKeys) LiSendKeyboardEvent(key.shortValue, KEY_ACTION_UP, 0);
    }
    [_heldDesktopKeys removeAllObjects];
    for (UIButton *button in _desktopShortcuts.arrangedSubviews) {
        button.backgroundColor = [UIColor colorWithWhite:0.17 alpha:1];
    }
}

- (void)moveTrackpad:(UIPanGestureRecognizer *)pan {
    if (!_streamReady) return;
    CGPoint delta = [pan translationInView:_trackpad];
    [pan setTranslation:CGPointZero inView:_trackpad];
    short dx = (short)MAX(SHRT_MIN, MIN(SHRT_MAX, lrint(delta.x * 2.0)));
    short dy = (short)MAX(SHRT_MIN, MIN(SHRT_MAX, lrint(delta.y * 2.0)));
    if (dx || dy) LiSendMouseMoveEvent(dx, dy);
}

- (void)clickTrackpad:(UITapGestureRecognizer *)tap {
    if (!_streamReady || tap.state != UIGestureRecognizerStateEnded) return;
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
    LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
}

- (void)showDesktopKeyboard {
    [_streamView toggleKeyboard];
    [_keyboardButton setTitle:[_streamView isKeyboardVisible] ? @"Hide Keyboard" : @"Keyboard"
                     forState:UIControlStateNormal];
}

- (void)confirmDesktopDisconnect {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Disconnect desktop?"
        message:@"The client will stop this stream without sending Quit App. Save work before disconnecting."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Keep Streaming" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Disconnect" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self returnToMainFrame];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return _streamView;
}

- (void)willMoveToParentViewController:(UIViewController *)parent {
    // Only cleanup when we're being destroyed
    if (parent == nil) {
        _didLeaveStream = YES;
        _streamReady = NO;
        [_controllerSupport cleanup];
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        [_streamMan stopStream];
        if (_inactivityTimer != nil) {
            [_inactivityTimer invalidate];
            _inactivityTimer = nil;
        }
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
}

#if 0
- (void)keyboardWillShow:(NSNotification *)notification {
    _keyboardSize = [[[notification userInfo] objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;

    [UIView animateWithDuration:0.3 animations:^{
        CGRect frame = self->_scrollView.frame;
        frame.size.height -= self->_keyboardSize.height;
        self->_scrollView.frame = frame;
    }];
}

-(void)keyboardWillHide:(NSNotification *)notification {
    // NOTE: UIKeyboardFrameEndUserInfoKey returns a different keyboard size
    // than UIKeyboardFrameBeginUserInfoKey, so it's unsuitable for use here
    // to undo the changes made by keyboardWillShow.
    
    [UIView animateWithDuration:0.3 animations:^{
        CGRect frame = self->_scrollView.frame;
        frame.size.height += self->_keyboardSize.height;
        self->_scrollView.frame = frame;
    }];
}
#endif

- (void)updateStatsOverlay {
    NSString* overlayText = [self->_streamMan getStatsOverlayText];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateOverlayText:overlayText];
    });
}

- (void)updateOverlayText:(NSString*)text {
    if (_overlayView == nil) {
        _overlayView = [[UITextView alloc] init];
#if !TARGET_OS_TV
        [_overlayView setEditable:NO];
#endif
        [_overlayView setUserInteractionEnabled:NO];
        [_overlayView setSelectable:NO];
        [_overlayView setScrollEnabled:NO];
        
        // HACK: If not using stats overlay, center the text
        if (_statsUpdateTimer == nil) {
            [_overlayView setTextAlignment:NSTextAlignmentCenter];
        }
        
        [_overlayView setTextColor:[UIColor lightGrayColor]];
        [_overlayView setBackgroundColor:[UIColor blackColor]];
#if TARGET_OS_TV
        [_overlayView setFont:[UIFont systemFontOfSize:24]];
#else
        [_overlayView setFont:[UIFont systemFontOfSize:12]];
#endif
        [_overlayView setAlpha:0.5];
        [self.view addSubview:_overlayView];
    }
    
    if (text != nil) {
        // We set our bounds to the maximum width in order to work around a bug where
        // sizeToFit interacts badly with the UITextView's line breaks, causing the
        // width to get smaller and smaller each time as more line breaks are inserted.
        [_overlayView setBounds:CGRectMake(self.view.frame.origin.x,
                                           _overlayView.frame.origin.y,
                                           self.view.frame.size.width,
                                           _overlayView.frame.size.height)];
        [_overlayView setText:text];
        [_overlayView sizeToFit];
        [_overlayView setCenter:CGPointMake(self.view.frame.size.width / 2, _overlayView.frame.size.height / 2)];
        [_overlayView setHidden:NO];
    }
    else {
        [_overlayView setHidden:YES];
    }
}

- (void) returnToMainFrame {
    [self releaseDesktopModifiers];
    // Reset display mode back to default
    [self updatePreferredDisplayMode:NO];
    
    [_statsUpdateTimer invalidate];
    _statsUpdateTimer = nil;
    
    [self.navigationController popToRootViewControllerAnimated:YES];
}

// This will fire if the user opens control center or gets a low battery message
- (void)applicationWillResignActive:(NSNotification *)notification {
    [self releaseDesktopModifiers];
    if (_inactivityTimer != nil) {
        [_inactivityTimer invalidate];
    }
    
}

- (void)inactiveTimerExpired:(NSTimer*)timer {
    Log(LOG_I, @"Terminating stream after inactivity");

    [self returnToMainFrame];
    
    _inactivityTimer = nil;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    _sceneIsBackgrounded = NO;
    // Stop the background timer, since we're foregrounded again
    if (_inactivityTimer != nil) {
        Log(LOG_I, @"Stopping inactivity timer after becoming active again");
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }
    if (_backgroundConnectionLost) {
        [self resumeStreamAfterBackground];
    } else {
        [self.view setNeedsLayout];
    }
}

// This fires when the home button is pressed
- (void)applicationDidEnterBackground:(UIApplication *)application {
    Log(LOG_I, @"Backgrounded; preserving host application session");

    if (_inactivityTimer != nil) {
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }
    
    _sceneIsBackgrounded = YES;
    ++_resizeGeneration;
    _resizeInFlight = NO;
    [self releaseDesktopModifiers];
    // iOS may suspend the transport. A later foreground resume uses the last
    // decoded host mode; this does not send Quit App or resize by reconnecting.
}

- (void)resumeStreamAfterBackground {
    if (_didLeaveStream || _sceneIsBackgrounded || !_backgroundConnectionLost) return;
    _backgroundConnectionLost = NO;
    _streamReady = NO;
    _resizeInFlight = NO;
    _requestedViewportPixels = CGSizeZero;
    _desiredViewportPixels = CGSizeZero;
    if (_decodedVideoPixels.width > 0 && _decodedVideoPixels.height > 0) {
        self.streamConfig.width = (int)_decodedVideoPixels.width;
        self.streamConfig.height = (int)_decodedVideoPixels.height;
    }
    _stageLabel.text = @"Resuming desktop…";
    _stageLabel.hidden = NO;
    [_spinner startAnimating];
    _streamMan = [[StreamManager alloc] initWithConfig:self.streamConfig
                                             renderView:_streamView connectionCallbacks:self];
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    [queue addOperation:_streamMan];
}

- (void)edgeSwiped {
    Log(LOG_I, @"User swiped to end stream");
    
    [self returnToMainFrame];
}

- (CGSize)advertisedModeForViewport:(CGSize)viewport {
    if (![_streamMan supportsLiveResolutionChange]) return CGSizeZero;
    LI_RESOLUTION_MODE modes[128];
    int count = LiGetLiveResizeModes(modes, 128);
    BOOL portrait = viewport.height > viewport.width;
    double targetAspect = viewport.width / viewport.height;
    double targetArea = viewport.width * viewport.height;
    double bestScore = DBL_MAX;
    CGSize best = CGSizeZero;
    for (int i = 0; i < count; i++) {
        if ((modes[i].height > modes[i].width) != portrait || modes[i].refreshRate != 60) continue;
        double aspect = (double)modes[i].width / modes[i].height;
        double area = (double)modes[i].width * modes[i].height;
        double score = fabs(log(aspect / targetAspect)) * 3.0 + fabs(log(area / targetArea)) * 0.35;
        if (score < bestScore) {
            bestScore = score;
            best = CGSizeMake(modes[i].width, modes[i].height);
        }
    }
    return best;
}

- (void)scheduleLiveResize {
    if (_didLeaveStream || !_streamReady || _sceneIsBackgrounded ||
        ![_streamMan supportsLiveResolutionChange]) return;
    CGSize desired = _desiredViewportPixels;
    if (desired.width < 2 || desired.height < 2 ||
        CGSizeEqualToSize(desired, _decodedVideoPixels) ||
        CGSizeEqualToSize(desired, _requestedViewportPixels)) return;

    NSUInteger generation = ++_resizeGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self->_didLeaveStream || !self->_streamReady || generation != self->_resizeGeneration ||
            self->_resizeInFlight || !CGSizeEqualToSize(desired, self->_desiredViewportPixels)) return;
        int result = [self->_streamMan requestLiveResolutionWidth:(unsigned int)desired.width
                                                          height:(unsigned int)desired.height];
        // Remember the attempted size even if the host rejects it silently. Never
        // loop on the same geometry or reconnect the application session.
        self->_requestedViewportPixels = desired;
        if (result != LI_RESOLUTION_CHANGE_OK) return;
        self->_resizeInFlight = YES;
        [self.view setNeedsLayout];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (self->_resizeInFlight && CGSizeEqualToSize(self->_requestedViewportPixels, desired)) {
                self->_resizeInFlight = NO;
                [self.view setNeedsLayout];
                if (!CGSizeEqualToSize(self->_desiredViewportPixels, desired)) [self scheduleLiveResize];
            }
        });
    });
}

- (void)hostResolutionAppliedWidth:(uint32_t)width height:(uint32_t)height {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_didLeaveStream) return;
        // Acknowledgement alone must not alter aspect or touch geometry.
        self->_hostAppliedPixels = CGSizeMake(width, height);
        if (self->_resizeInFlight &&
            !CGSizeEqualToSize(self->_hostAppliedPixels, self->_requestedViewportPixels)) {
            // The host retained its old mode: this request was rejected or fell
            // back. Keep the last decoded picture and clear the wait indicator.
            self->_resizeInFlight = NO;
            [self.view setNeedsLayout];
        }
    });
}

- (void)decodedVideoWidth:(uint32_t)width height:(uint32_t)height {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_didLeaveStream) return;
        self->_decodedVideoPixels = CGSizeMake(width, height);
        if (self.streamConfig.useSafeResizeBootstrap) {
            LI_RESOLUTION_MODE modes[128];
            int count = LiGetLiveResizeModes(modes, 128);
            for (int i = 0; i < count; i++) {
                if (modes[i].width == width && modes[i].height == height && modes[i].refreshRate == 60) {
                    NSString *key = [self.streamConfig confirmedModePreferenceKey];
                    if (key != nil) [[NSUserDefaults standardUserDefaults] setObject:
                        @{@"width": @(width), @"height": @(height)} forKey:key];
                    break;
                }
            }
        }
        if (CGSizeEqualToSize(self->_decodedVideoPixels, self->_requestedViewportPixels)) {
            self->_resizeInFlight = NO;
        }
        [self.view setNeedsLayout];
        if (!self->_resizeInFlight) [self scheduleLiveResize];
    });
}

- (void) connectionStarted {
    Log(LOG_I, @"Connection started");
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_didLeaveStream) return;
        self->_streamReady = YES;
        [self.view setNeedsLayout];
        // Leave the spinner spinning until it's obscured by
        // the first frame of video.
        self->_stageLabel.hidden = YES;
        self->_tipLabel.hidden = YES;
        
        [self->_streamView showOnScreenControls];
        
        [self->_controllerSupport connectionEstablished];
        
        if (self->_settings.statsOverlay) {
            self->_statsUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f
                                                                       target:self
                                                                     selector:@selector(updateStatsOverlay)
                                                                     userInfo:nil
                                                                      repeats:YES];
        }
    });
}

- (void)connectionTerminated:(int)errorCode {
    Log(LOG_I, @"Connection terminated: %d", errorCode);
    
    unsigned int portFlags = LiGetPortFlagsFromTerminationErrorCode(errorCode);
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443, portFlags);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_didLeaveStream) return;
        if (self->_sceneIsBackgrounded) {
            self->_backgroundConnectionLost = YES;
            self->_streamReady = NO;
            self->_resizeInFlight = NO;
            ++self->_resizeGeneration;
            return;
        }
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        NSString* title;
        NSString* message;
        
        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
            title = @"Connection Error";
            message = @"Your device's network connection is blocking Moonlight. Streaming may not work while connected to this network.";
        }
        else {
            switch (errorCode) {
                case ML_ERROR_GRACEFUL_TERMINATION:
                    [self returnToMainFrame];
                    return;
                    
                case ML_ERROR_NO_VIDEO_TRAFFIC:
                    title = @"Connection Error";
                    message = @"No video received from host.";
                    if (portFlags != 0) {
                        char failingPorts[256];
                        LiStringifyPortFlags(portFlags, "\n", failingPorts, sizeof(failingPorts));
                        message = [message stringByAppendingString:[NSString stringWithFormat:@"\n\nCheck your firewall and port forwarding rules for port(s):\n%s", failingPorts]];
                    }
                    break;
                    
                case ML_ERROR_NO_VIDEO_FRAME:
                    title = @"Connection Error";
                    message = @"Your network connection isn't performing well. Reduce your video bitrate setting or try a faster connection.";
                    break;
                    
                case ML_ERROR_UNEXPECTED_EARLY_TERMINATION:
                case ML_ERROR_PROTECTED_CONTENT:
                    title = @"Connection Error";
                    message = @"Something went wrong on your host PC when starting the stream.\n\nMake sure you don't have any DRM-protected content open on your host PC. You can also try restarting your host PC.\n\nIf the issue persists, try reinstalling your GPU drivers and GeForce Experience.";
                    break;
                    
                case ML_ERROR_FRAME_CONVERSION:
                    title = @"Connection Error";
                    message = @"The host PC reported a fatal video encoding error.\n\nTry disabling HDR mode, changing the streaming resolution, or changing your host PC's display resolution.";
                    break;
                    
                default:
                {
                    NSString* errorString;
                    if (abs(errorCode) > 1000) {
                        // We'll assume large errors are hex values
                        errorString = [NSString stringWithFormat:@"%08X", (uint32_t)errorCode];
                    }
                    else {
                        // Smaller values will just be printed as decimal (probably errno.h values)
                        errorString = [NSString stringWithFormat:@"%d", errorCode];
                    }
                    
                    title = @"Connection Terminated";
                    message = [NSString stringWithFormat: @"The connection was terminated\n\nError code: %@", errorString];
                    break;
                }
            }
        }
        
        UIAlertController* conTermAlert = [UIAlertController alertControllerWithTitle:title
                                                                              message:message
                                                                       preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:conTermAlert];
        [conTermAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:conTermAlert animated:YES completion:nil];
    });

    [_streamMan stopStream];
}

- (void) stageStarting:(const char*)stageName {
    Log(LOG_I, @"Starting %s", stageName);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_didLeaveStream) return;
        NSString* lowerCase = [NSString stringWithFormat:@"%s in progress...", stageName];
        NSString* titleCase = [[[lowerCase substringToIndex:1] uppercaseString] stringByAppendingString:[lowerCase substringFromIndex:1]];
        [self->_stageLabel setText:titleCase];
        [self->_stageLabel sizeToFit];
        self->_stageLabel.center = CGPointMake(self.view.frame.size.width / 2, self->_stageLabel.center.y);
    });
}

- (void) stageComplete:(const char*)stageName {
}

- (void) stageFailed:(const char*)stageName withError:(int)errorCode portTestFlags:(int)portTestFlags {
    Log(LOG_I, @"Stage %s failed: %d", stageName, errorCode);
    
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443, portTestFlags);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_didLeaveStream) return;
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        NSString* message = [NSString stringWithFormat:@"%s failed with error %d", stageName, errorCode];
        if (portTestFlags != 0) {
            char failingPorts[256];
            LiStringifyPortFlags(portTestFlags, "\n", failingPorts, sizeof(failingPorts));
            message = [message stringByAppendingString:[NSString stringWithFormat:@"\n\nCheck your firewall and port forwarding rules for port(s):\n%s", failingPorts]];
        }
        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
            message = [message stringByAppendingString:@"\n\nYour device's network connection is blocking Moonlight. Streaming may not work while connected to this network."];
        }
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Connection Failed"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:alert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
    
    [_streamMan stopStream];
}

- (void) launchFailed:(NSString*)message {
    Log(LOG_I, @"Launch failed: %@", message);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_didLeaveStream) return;
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Connection Error"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:alert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)rumble:(unsigned short)controllerNumber lowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor {
    Log(LOG_I, @"Rumble on gamepad %d: %04x %04x", controllerNumber, lowFreqMotor, highFreqMotor);
    
    [_controllerSupport rumble:controllerNumber lowFreqMotor:lowFreqMotor highFreqMotor:highFreqMotor];
}

- (void) rumbleTriggers:(uint16_t)controllerNumber leftTrigger:(uint16_t)leftTrigger rightTrigger:(uint16_t)rightTrigger {
    Log(LOG_I, @"Trigger rumble on gamepad %d: %04x %04x", controllerNumber, leftTrigger, rightTrigger);
    
    [_controllerSupport rumbleTriggers:controllerNumber leftTrigger:leftTrigger rightTrigger:rightTrigger];
}

- (void) setMotionEventState:(uint16_t)controllerNumber motionType:(uint8_t)motionType reportRateHz:(uint16_t)reportRateHz {
    Log(LOG_I, @"Set motion state on gamepad %d: %02x %u Hz", controllerNumber, motionType, reportRateHz);
    
    [_controllerSupport setMotionEventState:controllerNumber motionType:motionType reportRateHz:reportRateHz];
}

- (void) setControllerLed:(uint16_t)controllerNumber r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b {
    Log(LOG_I, @"Set controller LED on gamepad %d: l%02x%02x%02x", controllerNumber, r, g, b);
    
    [_controllerSupport setControllerLed:controllerNumber r:r g:g b:b];
}

- (void)connectionStatusUpdate:(int)status {
    Log(LOG_W, @"Connection status update: %d", status);

    // The stats overlay takes precedence over these warnings
    if (_statsUpdateTimer != nil) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (status) {
            case CONN_STATUS_OKAY:
                [self updateOverlayText:nil];
                break;
                
            case CONN_STATUS_POOR:
                if (self->_streamConfig.bitRate > 5000) {
                    [self updateOverlayText:@"Slow connection to PC\nReduce your bitrate"];
                }
                else {
                    [self updateOverlayText:@"Poor connection to PC"];
                }
                break;
        }
    });
}

- (void) updatePreferredDisplayMode:(BOOL)streamActive {
#if TARGET_OS_TV
    if (@available(tvOS 11.2, *)) {
        UIWindow* window = [[[UIApplication sharedApplication] delegate] window];
        AVDisplayManager* displayManager = [window avDisplayManager];
        
        // This logic comes from Kodi and MrMC
        if (streamActive) {
            int dynamicRange;
            
            if (LiGetCurrentHostDisplayHdrMode()) {
                dynamicRange = 2; // HDR10
            }
            else {
                dynamicRange = 0; // SDR
            }
            
            AVDisplayCriteria* displayCriteria = [[AVDisplayCriteria alloc] initWithRefreshRate:[_settings.framerate floatValue]
                                                                              videoDynamicRange:dynamicRange];
            displayManager.preferredDisplayCriteria = displayCriteria;
        }
        else {
            // Switch back to the default display mode
            displayManager.preferredDisplayCriteria = nil;
        }
    }
#endif
}

- (void) setHdrMode:(bool)enabled {
    Log(LOG_I, @"HDR is now: %s", enabled ? "active" : "inactive");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updatePreferredDisplayMode:YES];
    });
}

- (void) videoContentShown {
    [_spinner stopAnimating];
    [self.view setBackgroundColor:[UIColor blackColor]];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)gamepadPresenceChanged {
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

- (void)mousePresenceChanged {
#if !TARGET_OS_TV
    if (@available(iOS 14.0, *)) {
        [self setNeedsUpdateOfPrefersPointerLocked];
    }
#endif
}

- (void) streamExitRequested {
    Log(LOG_I, @"Gamepad combo requested stream exit");
    
    [self returnToMainFrame];
}

- (void)userInteractionBegan {
    // Disable hiding home bar when user is interacting.
    // iOS will force it to be shown anyway, but it will
    // also discard our edges deferring system gestures unless
    // we willingly give up home bar hiding preference.
    _userIsInteracting = YES;
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

- (void)userInteractionEnded {
    // Enable home bar hiding again if conditions allow
    _userIsInteracting = NO;
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

#if !TARGET_OS_TV
// Require a confirmation when streaming to activate a system gesture
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures {
    return UIRectEdgeAll;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    if ([_controllerSupport getConnectedGamepadCount] > 0 &&
        [_streamView getCurrentOscState] == OnScreenControlsLevelOff &&
        _userIsInteracting == NO) {
        // Autohide the home bar when a gamepad is connected
        // and the on-screen controls are disabled. We can't
        // do this all the time because any touch on the display
        // will cause the home indicator to reappear, and our
        // preferredScreenEdgesDeferringSystemGestures will also
        // be suppressed (leading to possible errant exits of the
        // stream).
        return YES;
    }
    
    return NO;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)prefersPointerLocked {
    // Pointer lock breaks the UIKit mouse APIs, which is a problem because
    // GCMouse is horribly broken on iOS 14.0 for certain mice. Only lock
    // the cursor if there is a GCMouse present.
    return [GCMouse mice].count > 0;
}
#endif

@end
