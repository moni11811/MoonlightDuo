//
//  StreamConfiguration.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "StreamConfiguration.h"
#import <CommonCrypto/CommonDigest.h>

@implementation StreamConfiguration
@synthesize host, httpsPort, appID, width, height, frameRate, bitRate, riKeyId, riKey, gamepadMask, appName, optimizeGameSettings, playAudioOnPC, swapABXYButtons, audioConfiguration, supportedVideoFormats, multiController, serverCert, rtspSessionUrl, serverCodecModeSupport;

- (NSString*)confirmedModePreferenceKey {
    if (self.serverCert.length == 0 || self.appID.length == 0) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(self.serverCert.bytes, (CC_LONG)self.serverCert.length, digest);
    NSMutableString *fingerprint = [NSMutableString string];
    for (NSUInteger i = 0; i < 16; i++) [fingerprint appendFormat:@"%02x", digest[i]];
    return [NSString stringWithFormat:@"MoonlightConfirmedMode.%@.%@", fingerprint, self.appID];
}
@end
