//
//  StreamConfiguration.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@interface StreamConfiguration : NSObject

// Desktop detaches without ending the host's app session. Gaming retains the
// existing Sunshine app launch flow.
@property BOOL desktopMode;
// 0 automatic (portrait controls), 1 desktop, 2 gaming. Presentation can
// change without changing the Sunshine app or Moonlight connection.
@property NSInteger presentationMode;
@property BOOL useSafeResizeBootstrap;

@property NSString* host;
@property unsigned short httpsPort;
@property NSString* appVersion;
@property NSString* gfeVersion;
@property NSString* appID;
@property NSString* appName;
@property NSString* rtspSessionUrl;
@property int serverCodecModeSupport;
@property int width;
@property int height;
@property int frameRate;
@property int bitRate;
@property int riKeyId;
@property NSData* riKey;
@property int gamepadMask;
@property BOOL optimizeGameSettings;
@property BOOL playAudioOnPC;
@property BOOL swapABXYButtons;
@property int audioConfiguration;
@property int supportedVideoFormats;
@property BOOL multiController;
@property BOOL useFramePacing;
@property NSData* serverCert;

// Paired-host/app scoped key; contains a digest, never the pairing certificate.
- (NSString*)confirmedModePreferenceKey;

@end
