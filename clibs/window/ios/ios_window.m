#include "../window.h"
#include "ios_window.h"
#include "window.h"

UIView* global_window = NULL;

@interface ViewController : UIViewController
@end
@implementation ViewController
- (BOOL)prefersStatusBarHidden {
    return YES;
}
@end

static id<MTLDevice> g_device = NULL;
static struct ant_window_callback* g_cb = NULL;

static void push_message(struct ant_window_message* msg) {
    if (g_cb) {
        g_cb->message(g_cb->ud, msg);
    }
}

@implementation View
+ (Class)layerClass  {
    Class metalClass = NSClassFromString(@"CAMetalLayer");
    if (metalClass != nil)  {
        g_device = MTLCreateSystemDefaultDevice();
        if (g_device) {
            return metalClass;
       }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [CAEAGLLayer class];
#pragma clang diagnostic pop
}
- (id)initWithRect:(CGRect)rect WithScale: (float)scale {
    self = [super initWithFrame:rect];
    if (nil == self) {
        return nil;
    }
    [self setContentScaleFactor: scale];

    global_window = self;

    int w = (int)(self.contentScaleFactor * self.frame.size.width);
    int h = (int)(self.contentScaleFactor * self.frame.size.height);
    struct ant_window_message msg;
    msg.type = ANT_WINDOW_INIT;
    msg.u.init.window = (__bridge void*)self.layer;
    msg.u.init.context = (__bridge void*)g_device;
    msg.u.init.w = w;
    msg.u.init.h = h;
    push_message(&msg);
    return self;
}
- (void)layoutSubviews {
    uint32_t frameW = (uint32_t)(self.contentScaleFactor * self.frame.size.width);
    uint32_t frameH = (uint32_t)(self.contentScaleFactor * self.frame.size.height);
    struct ant_window_message msg;
    msg.type = ANT_WINDOW_SIZE;
    msg.u.size.x = frameW;
    msg.u.size.y = frameH;
    msg.u.size.type = 0;
    push_message(&msg);
}
- (void)start {
    if (nil == self.m_displayLink) {
        self.m_displayLink = [self.window.screen displayLinkWithTarget:self selector:@selector(renderFrame)];
        [self.m_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    }
}
- (void)stop {
    if (nil != self.m_displayLink) {
        [self.m_displayLink invalidate];
        self.m_displayLink = nil;
    }
}
- (void)renderFrame {
    struct ant_window_message msg;
    msg.type = ANT_WINDOW_UPDATE;
    push_message(&msg);
}
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        CGPoint pt = [touch locationInView:self];
        pt.x *= self.contentScaleFactor;
        pt.y *= self.contentScaleFactor;
        struct ant_window_message msg;
        msg.type = ANT_WINDOW_TOUCH;
        msg.u.touch.id = (uintptr_t)touch;
        msg.u.touch.state = 1;
        msg.u.touch.x = pt.x;
        msg.u.touch.y = pt.y;
        push_message(&msg);
    }
}
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        CGPoint pt = [touch locationInView:self];
        pt.x *= self.contentScaleFactor;
        pt.y *= self.contentScaleFactor;
        struct ant_window_message msg;
        msg.type = ANT_WINDOW_TOUCH;
        msg.u.touch.id = (uintptr_t)touch;
        msg.u.touch.state = 3;
        msg.u.touch.x = pt.x;
        msg.u.touch.y = pt.y;
        push_message(&msg);
    }
}
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        CGPoint pt = [touch locationInView:self];
        pt.x *= self.contentScaleFactor;
        pt.y *= self.contentScaleFactor;
        struct ant_window_message msg;
        msg.type = ANT_WINDOW_TOUCH;
        msg.u.touch.id = (uintptr_t)touch;
        msg.u.touch.state = 2;
        msg.u.touch.x = pt.x;
        msg.u.touch.y = pt.y;
        push_message(&msg);
    }
}
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    CGRect rect = [[UIScreen mainScreen] bounds];
    float scale = [[UIScreen mainScreen] scale];
    self.m_window = [[UIWindow alloc] initWithFrame: rect];
    
    [self.m_window setBackgroundColor:[UIColor whiteColor]];
    
    self.m_view = [[View alloc] initWithRect: rect WithScale: scale];
    self.m_view.multipleTouchEnabled = true;
    //[self.m_window addSubview: self.m_view];

    ViewController* mvc = [[ViewController alloc] init];
    mvc.view = self.m_view;
    [self.m_window setRootViewController: mvc];
    [self.m_window makeKeyAndVisible];
    [self.m_view start];
    return YES;
}
- (void) applicationWillTerminate:(UIApplication *)application {
    struct ant_window_message msg;
    msg.type = ANT_WINDOW_EXIT;
    push_message(&msg);
    [self.m_view stop];
}
- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    return UIInterfaceOrientationMaskLandscape;
}
@end

int window_init(struct ant_window_callback* cb) {
    g_cb = cb;
    return 0;
}

int window_create(struct ant_window_callback* cb, int w, int h) {
    // do nothing
    return 0;
}

void window_mainloop(struct ant_window_callback* cb, int update) {
    int argc = 0;
    char **argv = 0;
    UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
}
