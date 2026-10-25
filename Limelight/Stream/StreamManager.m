//
//  StreamManager.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "StreamManager.h"
#import "CryptoManager.h"
#import "HttpManager.h"
#import "Utils.h"

#import "StreamView.h"
#import "ServerInfoResponse.h"
#import "HttpResponse.h"
#import "HttpRequest.h"
#import "IdManager.h"

#include <Limelight.h>
#include <stdatomic.h>
#import <VideoToolbox/VideoToolbox.h>

@implementation StreamManager {
    StreamConfiguration* _config;

    UIView* _renderView;
    __weak id<ConnectionCallbacks> _callbacks;
    Connection* _connection;
    atomic_bool _stopRequested;
}

- (id) initWithConfig:(StreamConfiguration*)config renderView:(UIView*)view connectionCallbacks:(id<ConnectionCallbacks>)callbacks {
    self = [super init];
    _config = config;
    atomic_init(&_stopRequested, false);
    _renderView = view;
    _callbacks = callbacks;
    _config.riKey = [Utils randomBytes:16];
    _config.riKeyId = arc4random();
    return self;
}

- (void)main {
    if (atomic_load(&_stopRequested)) return;
    [CryptoManager generateKeyPairUsingSSL];
    
    HttpManager* hMan = [[HttpManager alloc] initWithAddress:_config.host httpsPort:_config.httpsPort
                                                     serverCert:_config.serverCert];
    
    ServerInfoResponse* serverInfoResp = [[ServerInfoResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:serverInfoResp withUrlRequest:[hMan newServerInfoRequest:false]
                                       fallbackError:401 fallbackRequest:[hMan newHttpServerInfoRequest]]];
    if (atomic_load(&_stopRequested)) return;
    NSString* pairStatus = [serverInfoResp getStringTag:@"PairStatus"];
    NSString* appversion = [serverInfoResp getStringTag:@"appversion"];
    NSString* gfeVersion = [serverInfoResp getStringTag:@"GfeVersion"];
    NSString* serverState = [serverInfoResp getStringTag:@"state"];
    if (![serverInfoResp isStatusOk]) {
        [self reportLaunchFailure:serverInfoResp.statusMessage];
        return;
    }
    else if (pairStatus == NULL || appversion == NULL || serverState == NULL) {
        [self reportLaunchFailure:@"Failed to connect to PC"];
        return;
    }
    
    if (![pairStatus isEqualToString:@"1"]) {
        // Not paired
        [self reportLaunchFailure:@"Device not paired to PC"];
        return;
    }
    
    // Only perform this check on GFE (as indicated by MJOLNIR in state value)
    if ((_config.width > 4096 || _config.height > 4096) && [serverState containsString:@"MJOLNIR"]) {
        // Pascal added support for 8K HEVC encoding support. Maxwell 2 could encode HEVC but only up to 4K.
        // We can't directly identify Pascal, but we can look for HEVC Main10 which was added in the same generation.
        NSString* codecSupport = [serverInfoResp getStringTag:@"ServerCodecModeSupport"];
        if (codecSupport == nil || !([codecSupport intValue] & 0x200)) {
            [self reportLaunchFailure:@"Your host PC's GPU doesn't support streaming video resolutions over 4K."];
            return;
        }
    }
    
    // Populate the config's version fields from serverinfo
    _config.appVersion = appversion;
    _config.gfeVersion = gfeVersion;
    if (_config.useSafeResizeBootstrap) {
        // HTTP launch and RTSP ANNOUNCE must describe the same published,
        // encoder-safe starting mode. Desired viewport geometry is selected
        // only after this connection has advertised its live mode list.
        if (!VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)) {
            [self reportLaunchFailure:@"This device cannot decode the host's HEVC stream."];
            return;
        }
        int width = 1920, height = 1080;
        NSString *key = [_config confirmedModePreferenceKey];
        NSDictionary *saved = key == nil ? nil : [[NSUserDefaults standardUserDefaults] dictionaryForKey:key];
        NSNumber *savedWidth = saved[@"width"], *savedHeight = saved[@"height"];
        if ([savedWidth isKindOfClass:NSNumber.class] && [savedHeight isKindOfClass:NSNumber.class]) {
            NSInteger w = savedWidth.integerValue, h = savedHeight.integerValue;
            if (w >= 256 && w <= 3840 && h >= 256 && h <= 3840 &&
                !(w & 1) && !(h & 1) && w * h <= 8294400) {
                width = (int)w;
                height = (int)h;
            }
        }
        _config.width = width;
        _config.height = height;
        _config.frameRate = 60;
        _config.optimizeGameSettings = YES;
        _config.supportedVideoFormats = VIDEO_FORMAT_H265;
    }
    if (atomic_load(&_stopRequested)) return;
    
    // resumeApp and launchApp handle calling launchFailed
    NSString* sessionUrl;
    if ([serverState hasSuffix:@"_SERVER_BUSY"]) {
        // App already running, resume it
        if (![self resumeApp:hMan receiveSessionUrl:&sessionUrl]) {
            return;
        }
    } else {
        // Start app
        if (![self launchApp:hMan receiveSessionUrl:&sessionUrl]) {
            return;
        }
    }
    if (atomic_load(&_stopRequested)) return;
    
    // Populate RTSP session URL from launch/resume response
    _config.rtspSessionUrl = sessionUrl;
    
    // Initializing the renderer must be done on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        if (atomic_load(&self->_stopRequested)) return;
        VideoDecoderRenderer* renderer = [[VideoDecoderRenderer alloc] initWithView:self->_renderView callbacks:self->_callbacks streamAspectRatio:(float)self->_config.width / (float)self->_config.height useFramePacing:self->_config.useFramePacing];
        self->_connection = [[Connection alloc] initWithConfig:self->_config renderer:renderer connectionCallbacks:self->_callbacks];
        if (atomic_load(&self->_stopRequested)) {
            [self->_connection terminate];
            return;
        }
        NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
        [opQueue addOperation:self->_connection];
    });
}

- (void) stopStream
{
    atomic_store(&_stopRequested, true);
    [self cancel];
    [_connection terminate];
}

- (BOOL)supportsLiveResolutionChange {
    LI_RESOLUTION_MODE mode;
    return !atomic_load(&_stopRequested) &&
           (LiGetHostFeatureFlags() & LI_FF_CLIENT_RESOLUTION_CHANGE) != 0 &&
           LiGetLiveResizeModes(&mode, 1) > 0;
}

- (int)requestLiveResolutionWidth:(unsigned int)width height:(unsigned int)height {
    if (atomic_load(&_stopRequested)) return LI_RESOLUTION_CHANGE_ERR_NOT_CONNECTED;
    return LiSendResolutionChangeRequest(width, height);
}

- (void)reportLaunchFailure:(NSString *)message {
    if (!atomic_load(&_stopRequested)) {
        [_callbacks launchFailed:message];
    }
}

- (BOOL) launchApp:(HttpManager*)hMan receiveSessionUrl:(NSString**)sessionUrl {
    HttpResponse* launchResp = [[HttpResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:launchResp withUrlRequest:[hMan newLaunchOrResumeRequest:@"launch" config:_config]]];
    NSString *gameSession = [launchResp getStringTag:@"gamesession"];
    if (![launchResp isStatusOk]) {
        [self reportLaunchFailure:launchResp.statusMessage];
        Log(LOG_E, @"Failed Launch Response: %@", launchResp.statusMessage);
        return FALSE;
    } else if (gameSession == NULL || [gameSession isEqualToString:@"0"]) {
        [self reportLaunchFailure:@"Failed to launch app"];
        Log(LOG_E, @"Failed to parse game session");
        return FALSE;
    }
    
    *sessionUrl = [launchResp getStringTag:@"sessionUrl0"];
    return TRUE;
}

- (BOOL) resumeApp:(HttpManager*)hMan receiveSessionUrl:(NSString**)sessionUrl {
    HttpResponse* resumeResp = [[HttpResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:resumeResp withUrlRequest:[hMan newLaunchOrResumeRequest:@"resume" config:_config]]];
    NSString* resume = [resumeResp getStringTag:@"resume"];
    if (![resumeResp isStatusOk]) {
        [self reportLaunchFailure:resumeResp.statusMessage];
        Log(LOG_E, @"Failed Resume Response: %@", resumeResp.statusMessage);
        return FALSE;
    } else if (resume == NULL || [resume isEqualToString:@"0"]) {
        [self reportLaunchFailure:@"Failed to resume app"];
        Log(LOG_E, @"Failed to parse resume response");
        return FALSE;
    }
    
    *sessionUrl = [resumeResp getStringTag:@"sessionUrl0"];
    return TRUE;
}

- (NSString*) getStatsOverlayText {
    video_stats_t stats;
    
    if (!_connection) {
        return nil;
    }
    
    if (![_connection getVideoStats:&stats]) {
        return nil;
    }
    
    uint32_t rtt, variance;
    NSString* latencyString;
    if (LiGetEstimatedRttInfo(&rtt, &variance)) {
        latencyString = [NSString stringWithFormat:@"%u ms (variance: %u ms)", rtt, variance];
    }
    else {
        latencyString = @"N/A";
    }
    
    NSString* hostProcessingString;
    if (stats.framesWithHostProcessingLatency != 0) {
        hostProcessingString = [NSString stringWithFormat:@"\nHost processing latency min/max/avg: %.1f/%.1f/%.1f ms",
                                stats.minHostProcessingLatency / 10.f,
                                stats.maxHostProcessingLatency / 10.f,
                                (float)stats.totalHostProcessingLatency / stats.framesWithHostProcessingLatency / 10.f];
    }
    else {
        hostProcessingString = @"";
    }
    
    float interval = stats.endTime - stats.startTime;
    return [NSString stringWithFormat:@"Video stream: %dx%d %.2f FPS (Codec: %@)\nFrames dropped by your network connection: %.2f%%\nAverage network latency: %@%@",
            _config.width,
            _config.height,
            stats.totalFrames / interval,
            [_connection getActiveCodecName],
            stats.networkDroppedFrames / interval,
            latencyString,
            hostProcessingString];
}

@end
