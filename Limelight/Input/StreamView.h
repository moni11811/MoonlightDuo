//
//  StreamView.h
//  Moonlight
//
//  Created by Cameron Gutman on 10/19/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "ControllerSupport.h"
#import "OnScreenControls.h"
#import "Moonlight-Swift.h"
#import "StreamConfiguration.h"

@protocol UserInteractionDelegate <NSObject>

- (void) userInteractionBegan;
- (void) userInteractionEnded;

@end

#if TARGET_OS_TV
@interface StreamView : UIView <X1KitMouseDelegate, UITextFieldDelegate>
#else
@interface StreamView : UIView <X1KitMouseDelegate, UITextFieldDelegate, UIPointerInteractionDelegate>
#endif

- (void) setupStreamView:(ControllerSupport*)controllerSupport
     interactionDelegate:(id<UserInteractionDelegate>)interactionDelegate
                  config:(StreamConfiguration*)streamConfig;
- (void) showOnScreenControls;
- (void) setDesktopControlsHidden:(BOOL)hidden;
- (OnScreenControlsLevel) getCurrentOscState;
- (void) setVideoLayer:(CALayer *)videoLayer;
- (void) setDecodedVideoWidth:(uint32_t)width height:(uint32_t)height;
- (void) showKeyboard;
- (void) toggleKeyboard;
- (BOOL) isKeyboardVisible;

#if !TARGET_OS_TV
- (void) setGamingRevealExclusionRect:(CGRect)rect;
- (void) updateCursorLocation:(CGPoint)location isMouse:(BOOL)isMouse;
#endif

@end
