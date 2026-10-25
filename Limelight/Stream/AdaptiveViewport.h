#ifndef ADAPTIVE_VIEWPORT_H
#define ADAPTIVE_VIEWPORT_H

#include <math.h>

typedef struct { double width, height; } AVSize;
typedef struct { double top, left, bottom, right; } AVInsets;
typedef struct { double x, y; } AVPoint;
typedef struct { double x, y, width, height; } AVRect;

typedef enum { AVLayoutAutomatic, AVLayoutDesktop, AVLayoutGaming } AVLayoutMode;

static inline int AVUsesDesktopLayout(AVSize window, AVLayoutMode preference) {
    if (preference == AVLayoutDesktop) return 1;
    if (preference == AVLayoutGaming) return 0;
    // A fold hinge is not inferred from a product name or aspect ratio. This
    // size fallback covers portrait; book posture needs a platform signal or
    // the manual override.
    return window.height > window.width;
}

// UIKit reports hinge status on iOS 27.1. Unknown leaves the size fallback in
// place; a partially open book needs desktop controls even when landscape.
static inline int AVUsesDesktopLayoutWithHinge(AVSize window, AVLayoutMode preference, int hingeStatus) {
    if (preference != AVLayoutAutomatic) return AVUsesDesktopLayout(window, preference);
    if (hingeStatus == 2) return 1; // partially open book posture
    return AVUsesDesktopLayout(window, AVLayoutAutomatic);
}

// Desktop presentation dedicates a separate control surface below the stream.
// The encoded size must be based on this remote viewport, not the whole scene.
static inline AVRect AVRemoteViewport(AVSize safe, int desktop) {
    if (!desktop) return (AVRect){0, 0, safe.width, safe.height};
    // The upright desktop uses a stable 16:10 picture with its own margins.
    // Keep the toolbar, shortcut row, and trackpad outside the encoded pane.
    if (safe.height > safe.width) {
        double width = fmax(0, safe.width - 16);
        double height = fmin(width / 1.6, fmax(0, safe.height - 256));
        return (AVRect){8, 8, width, height};
    }
    double pane = fmin(safe.height - 160, fmax(160, safe.width / 1.6 + 16));
    pane = fmax(0, pane);
    return (AVRect){0, 0, safe.width, pane};
}

// The division region already includes interaction margins. Keep the stream
// entirely on one side of an active crease and controls on the other.
static inline AVRect AVRemoteViewportWithDivision(AVSize safe, AVRect division, int active) {
    if (!active || division.width <= 0 || division.height <= 0) return AVRemoteViewport(safe, 1);
    if (division.height > division.width) {
        return (AVRect){0, 0, fmax(0, fmin(safe.width, division.x)), safe.height};
    }
    return (AVRect){0, 0, safe.width, fmax(0, fmin(safe.height, division.y))};
}

// Video encoders and 4:2:0 surfaces need even pixel dimensions. Never round up
// beyond the drawable window supplied by the system.
static inline AVSize AVEncodedSize(double width, double height, double scale) {
    if (!isfinite(width) || !isfinite(height) || !isfinite(scale) ||
        width <= 0 || height <= 0 || scale <= 0) return (AVSize){0, 0};
    return (AVSize){floor(width * scale / 2.0) * 2.0,
                    floor(height * scale / 2.0) * 2.0};
}

static inline AVSize AVSafeEncodedSize(AVSize window, AVInsets insets, double scale) {
    return AVEncodedSize(fmax(0, window.width - insets.left - insets.right),
                         fmax(0, window.height - insets.top - insets.bottom), scale);
}

static inline AVRect AVFitRect(AVSize viewport, AVSize video) {
    if (viewport.width <= 0 || viewport.height <= 0 ||
        video.width <= 0 || video.height <= 0) return (AVRect){0, 0, 0, 0};
    double factor = fmin(viewport.width / video.width, viewport.height / video.height);
    double width = video.width * factor, height = video.height * factor;
    return (AVRect){(viewport.width - width) / 2.0, (viewport.height - height) / 2.0,
                    width, height};
}

// Coordinates must already be in the StreamView's local space (UIKit's
// locationInView: includes inverse UIScrollView zoom transforms).
static inline AVPoint AVMapPointToVideo(AVPoint point, AVRect fitted, AVSize video) {
    if (fitted.width <= 0 || fitted.height <= 0) return (AVPoint){0, 0};
    double x = fmin(fmax((point.x - fitted.x) / fitted.width, 0), 1);
    double y = fmin(fmax((point.y - fitted.y) / fitted.height, 0), 1);
    return (AVPoint){x * video.width, y * video.height};
}

#endif
