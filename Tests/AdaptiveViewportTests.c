#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "../Limelight/Stream/AdaptiveViewport.h"

static int near(double a, double b) { return fabs(a-b) < 0.001; }
int main(void) {
    AVSize folded = AVEncodedSize(2853, 2007, 1);
    assert(folded.width == 2852 && folded.height == 2006);
    AVSize landscape = AVEncodedSize(1000, 700, 3);
    assert(landscape.width == 3000 && landscape.height == 2100);
    AVSize safe = AVSafeEncodedSize((AVSize){1000, 700}, (AVInsets){0, 47, 0, 34}, 3);
    assert(safe.width == 2756 && safe.height == 2100);
    AVRect fit = AVFitRect((AVSize){1000, 700}, (AVSize){1600, 900});
    assert(near(fit.x, 0) && near(fit.y, 68.75));
    assert(near(fit.width, 1000) && near(fit.height, 562.5));
    AVPoint center = AVMapPointToVideo((AVPoint){500,350}, fit, (AVSize){1600,900});
    assert(near(center.x, 800) && near(center.y, 450));
    AVPoint outside = AVMapPointToVideo((AVPoint){-10,0}, fit, (AVSize){1600,900});
    assert(near(outside.x, 0) && near(outside.y, 0));
    AVRect rotated = AVFitRect((AVSize){700, 1000}, (AVSize){900, 1600});
    assert(rotated.width <= 700 && rotated.height <= 1000);
    assert(AVUsesDesktopLayout((AVSize){466, 678}, AVLayoutAutomatic));
    assert(!AVUsesDesktopLayout((AVSize){951, 669}, AVLayoutAutomatic));
    assert(AVUsesDesktopLayout((AVSize){951, 669}, AVLayoutDesktop));
    assert(!AVUsesDesktopLayout((AVSize){466, 678}, AVLayoutGaming));
    assert(AVUsesDesktopLayoutWithHinge((AVSize){951, 669}, AVLayoutAutomatic, 2));
    assert(!AVUsesDesktopLayoutWithHinge((AVSize){951, 669}, AVLayoutAutomatic, 1));
    assert(!AVUsesDesktopLayoutWithHinge((AVSize){951, 669}, AVLayoutAutomatic, 3));
    assert(!AVUsesDesktopLayoutWithHinge((AVSize){951, 669}, AVLayoutGaming, 2));
    AVRect book = AVRemoteViewportWithDivision((AVSize){951, 669}, (AVRect){455, 0, 40, 669}, 1);
    assert(near(book.width, 455) && near(book.height, 669));
    AVRect laptop = AVRemoteViewportWithDivision((AVSize){669, 951}, (AVRect){0, 455, 669, 40}, 1);
    assert(near(laptop.width, 669) && near(laptop.height, 455));
    AVRect portrait = AVRemoteViewport((AVSize){466, 678}, 1);
    assert(near(portrait.x, 8) && near(portrait.y, 8));
    assert(near(portrait.width, 450) && near(portrait.height, 281.25));
    assert(678 - (portrait.y + portrait.height) > 256);
    assert(near(AVRemoteViewport((AVSize){951, 669}, 0).height, 669));
    AVSize portraitPixels = AVEncodedSize(portrait.width, portrait.height, 3);
    assert(((int)portraitPixels.width % 2) == 0 && ((int)portraitPixels.height % 2) == 0);
    puts("AdaptiveViewport tests passed");
}
