#import <Cocoa/Cocoa.h>
#include <stdbool.h>
extern void DevDumpMetadata(void);
extern NSDictionary *DevRuntimeSnapshot(void);
extern void DevControlsShow(void);
extern void DevControlsAttach(NSTabView *);
extern void DevControlsRefresh(NSString *, NSDictionary *);
extern void DevAudioBatch(const float *, int, bool);
extern void DevAudioInterrupt(void);

// The ABI is taken from the installed UnityBridge. These delegates are registered
// by the original IL2CPP player. This file contains no replacement 3D rendering.
static void (*loadCharacter)(const char *, const char *);
static void (*unloadCharacter)(void);
static void (*playEffect)(const char *, bool);
static void (*changeCamera)(int32_t);
static void (*changeBackground)(int32_t);
static void (*setBackgroundAlpha)(float);
static void (*setListening)(bool);
static void (*interrupt)(void);
static void (*setFPS)(bool);
static void (*setActivities)(bool);
static bool ready, loaded;
static NSString *character = @"yuki";
static NSMutableArray<NSString *> *events;
static NSTextView *logView;
static NSTextField *status, *bodyState, *faceState, *effectState;
static NSWindow *panel;
static NSWindow *sceneWindow;
static NSView *sidebar;
static NSMutableArray<NSControl *> *sceneControls, *loadControls;
static NSMutableArray<NSButton *> *effectButtons;
static NSPopUpButton *characterPicker, *cameraPicker, *backgroundPicker;
static NSButton *listenToggle, *fpsToggle;
static NSDictionary *catalog;
static NSSet *activeEffects;
static NSInteger selectedCamera = 3, selectedBackground = 1;
static NSSlider *alphaSlider;
static NSString *nativeScene, *pendingScene, *pendingConfig;

static void record(NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!events) events = [NSMutableArray new];
        NSString *line = [NSString stringWithFormat:@"%@  %@", [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle], message];
        [events addObject:line];
        if (events.count > 200) [events removeObjectAtIndex:0];
        logView.string = [events componentsJoinedByString:@"\n"];
        [logView scrollRangeToVisible:NSMakeRange(logView.string.length, 0)];
        fprintf(stderr, "[Playground] %s\n", message.UTF8String);
    });
}

@interface Playground : NSObject
- (void)action:(NSControl *)sender;
- (void)build;
@end
static Playground *controller;

static NSTextField *label(NSString *text, CGFloat x, CGFloat y, CGFloat width, CGFloat size) {
    NSTextField *v = [NSTextField labelWithString:text];
    v.frame = NSMakeRect(x,y,width,24); v.font = [NSFont systemFontOfSize:size weight:NSFontWeightMedium];
    v.lineBreakMode = NSLineBreakByTruncatingTail;
    [sidebar addSubview:v]; return v;
}
static NSButton *button(NSString *text, NSString *command, CGFloat x, CGFloat y, CGFloat width, BOOL needsScene) {
    NSButton *b = [NSButton buttonWithTitle:text target:controller action:@selector(action:)];
    b.identifier = command; b.frame = NSMakeRect(x,y,width,30); b.bezelStyle = NSBezelStyleRounded;
    b.toolTip = command; [sidebar addSubview:b];
    if (needsScene) { [sceneControls addObject:b]; b.enabled = loaded; }
    return b;
}
static NSPopUpButton *picker(NSString *command, CGFloat y, NSArray<NSString *> *names, CGFloat width) {
    NSPopUpButton *p = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(126,y,width,28) pullsDown:NO];
    [p addItemsWithTitles:names]; p.identifier = command; p.target = controller; p.action = @selector(action:);
    [sidebar addSubview:p]; [sceneControls addObject:p]; p.enabled = loaded;
    return p;
}
static void sceneEnabled(BOOL enabled) {
    loaded = enabled;
    for (NSControl *c in sceneControls) c.enabled = enabled;
    for (NSControl *c in loadControls) c.enabled = ready;
    NSArray *supported = catalog[character][@"effects"];
    NSInteger position = 0;
    for (NSButton *b in effectButtons) {
        NSString *effect = [b.identifier substringFromIndex:7];
        b.enabled = enabled && [supported containsObject:effect];
        b.hidden = ![supported containsObject:effect];
        if (!b.hidden) {
            [b setFrameOrigin:NSMakePoint(20+(position%3)*128,635-(position/3)*34)];
            [b setButtonType:[supported containsObject:[@"stop_" stringByAppendingString:effect]] ? NSButtonTypePushOnPushOff : NSButtonTypeMomentaryPushIn];
            position++;
        }
        b.state = [activeEffects containsObject:effect] ? NSControlStateValueOn : NSControlStateValueOff;
    }
}
static void load(NSString *name) {
    if (!ready || !loadCharacter || !catalog[name]) return;
    character = name; activeEffects = [NSSet set]; sceneEnabled(NO);
    [characterPicker selectItemWithTitle:catalog[name][@"displayName"] ?: catalog[name][@"sceneId"]];
    [cameraPicker removeAllItems]; [backgroundPicker removeAllItems];
    for (NSDictionary *entry in catalog[name][@"cameras"])
        [cameraPicker addItemWithTitle:[NSString stringWithFormat:@"%@ · %@",entry[@"index"],entry[@"name"]]];
    for (NSDictionary *entry in catalog[name][@"backgrounds"])
        [backgroundPicker addItemWithTitle:[NSString stringWithFormat:@"%@ · %@",entry[@"index"],entry[@"name"]]];
    selectedCamera = MAX(0,MIN(selectedCamera,cameraPicker.numberOfItems-1));
    selectedBackground = MAX(0,MIN(selectedBackground,backgroundPicker.numberOfItems-1));
    for (NSControl *c in loadControls) c.enabled = NO;
    status.stringValue = [@"Загрузка сцены · " stringByAppendingString:name.capitalizedString];
    record([@"→ LoadCharacter " stringByAppendingString:catalog[name][@"sceneId"]]);
    [NSUserDefaults.standardUserDefaults setObject:name forKey:@"PlaygroundCharacter"];
    NSMutableDictionary *envelope=[@{@"characterSceneConfig":@{@"cameraIndex":@(selectedCamera),@"backgroundIndex":@(selectedBackground),@"backgroundAlpha":@1}} mutableCopy];
    if(catalog[name][@"animationConfig"])envelope[@"animationConfig"]=catalog[name][@"animationConfig"];
    NSString *config=[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:envelope options:0 error:nil] encoding:NSUTF8StringEncoding];
    NSString *sceneId=catalog[name][@"sceneId"];
    // Unity skips loading an already active scene; unload before reloading it.
    if([nativeScene isEqualToString:sceneId] && unloadCharacter){pendingScene=sceneId;pendingConfig=config;unloadCharacter();}
    else loadCharacter(sceneId.UTF8String, config.UTF8String);
}
static void stopEffects(void) {
    for (NSString *effect in catalog[character][@"effects"]) {
        if ([effect hasPrefix:@"stop_"] && playEffect) playEffect(effect.UTF8String, false);
    }
    if (setListening) setListening(false);
    if (interrupt) interrupt();
    listenToggle.state = NSControlStateValueOff;
}
static NSString *stateText(id value) {
    return [value isKindOfClass:NSArray.class] && [value count] ? [value componentsJoinedByString:@", "] : @"—";
}

@implementation Playground
- (void)action:(NSControl *)sender {
    NSString *cmd = sender.identifier;
    if ([cmd isEqualToString:@"character"]) { load(characterPicker.titleOfSelectedItem.lowercaseString); return; }
    if ([cmd hasPrefix:@"load:"]) { load([cmd substringFromIndex:5]); return; }
    if ([cmd isEqualToString:@"logs"]) {
        [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/AnimatesDev/Unity.log"]]];
        return;
    }
    if (!loaded) return;
    if ([cmd isEqualToString:@"advanced"]) { DevControlsShow(); return; }
    if ([cmd hasPrefix:@"effect:"] && playEffect) {
        NSString *effect = [cmd substringFromIndex:7];
        NSString *stop = [@"stop_" stringByAppendingString:effect];
        if ([activeEffects containsObject:effect] && [catalog[character][@"effects"] containsObject:stop]) effect = stop;
        record([@"→ PlayEffect " stringByAppendingString:effect]);
        playEffect(effect.UTF8String, false);
    } else if ([cmd isEqualToString:@"camera"] && changeCamera) {
        record([@"→ Camera " stringByAppendingString:cameraPicker.titleOfSelectedItem]);
        selectedCamera = cameraPicker.indexOfSelectedItem;
        [NSUserDefaults.standardUserDefaults setInteger:selectedCamera forKey:@"PlaygroundCamera"];
        changeCamera((int32_t)selectedCamera);
    } else if ([cmd isEqualToString:@"background"] && changeBackground) {
        record([@"→ Background " stringByAppendingString:backgroundPicker.titleOfSelectedItem]);
        selectedBackground = backgroundPicker.indexOfSelectedItem;
        [NSUserDefaults.standardUserDefaults setInteger:selectedBackground forKey:@"PlaygroundBackground"];
        changeBackground((int32_t)selectedBackground);
    } else if ([cmd isEqualToString:@"stop"]) { record(@"→ Stop effects / interrupt generation"); stopEffects(); }
    else if ([cmd isEqualToString:@"listening"] && setListening) {
        record(listenToggle.state ? @"→ Listening ON" : @"→ Listening OFF");
        setListening(listenToggle.state == NSControlStateValueOn);
    } else if ([cmd isEqualToString:@"fps"] && setFPS) setFPS(fpsToggle.state == NSControlStateValueOn);
    else if ([cmd isEqualToString:@"alpha"] && setBackgroundAlpha) setBackgroundAlpha(sender.floatValue);
}
- (void)build {
    if (panel) return;
    NSData *data = [NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"PlaygroundCatalog" ofType:@"json"]];
    catalog = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (!catalog) { record(@"Missing PlaygroundCatalog.json"); return; }
    NSUserDefaults *preferences = NSUserDefaults.standardUserDefaults;
    [preferences registerDefaults:@{@"PlaygroundCamera":@3,@"PlaygroundBackground":@1}];
    selectedCamera = MAX(0,MIN(5,[preferences integerForKey:@"PlaygroundCamera"]));
    selectedBackground = MAX(0,MIN(1,[preferences integerForKey:@"PlaygroundBackground"]));
    sceneControls = [NSMutableArray new]; loadControls = [NSMutableArray new]; effectButtons = [NSMutableArray new];
    activeEffects = [NSSet set];
    // Unity derives its camera aspect from the native window, so its view must
    // occupy the full content area. Attach the controls as a separate child
    // window; never compress or reparent the PlayerWindowView.
    for (NSWindow *w in NSApp.windows) {
        if (w.contentView && [NSStringFromClass(w.contentView.class) containsString:@"Player"]) { sceneWindow = w; break; }
    }
    if (!sceneWindow) sceneWindow = NSApp.mainWindow ?: NSApp.windows.firstObject;
    if (!sceneWindow) { record(@"Unity window is not ready"); return; }
    NSRect screen = NSScreen.mainScreen.visibleFrame;
    CGFloat height = MIN(820, screen.size.height-50);
    CGFloat width = MIN(1360, screen.size.width-40);
    sceneWindow.styleMask = NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable;
    [sceneWindow setContentSize:NSMakeSize(width-578,height)];
    [sceneWindow setFrameTopLeftPoint:NSMakePoint(NSMinX(screen)+20,NSMaxY(screen)-20)];
    sceneWindow.title = @"Animates Dev · Original Unity";
    panel = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,570,height) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    NSView *header=[[NSView alloc]initWithFrame:NSMakeRect(0,height-110,570,110)];
    header.autoresizingMask=NSViewMinYMargin;[panel.contentView addSubview:header];
    NSTabView *tabs=[[NSTabView alloc]initWithFrame:NSMakeRect(8,0,554,height-110)];
    tabs.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;[panel.contentView addSubview:tabs];
    NSScrollView *sidebarScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,550,height-140)];
    sidebarScroll.hasVerticalScroller = YES; sidebarScroll.autohidesScrollers = YES;
    NSView *overview=[[NSView alloc]initWithFrame:NSMakeRect(0,0,550,710)];
    sidebar = [[NSView alloc] initWithFrame:NSMakeRect(65,0,420,710)];
    [overview addSubview:sidebar];sidebarScroll.documentView=overview;
    NSTabViewItem *overviewTab=[[NSTabViewItem alloc]initWithIdentifier:@"effects"];overviewTab.label=@"Эффекты";overviewTab.view=sidebarScroll;[tabs addTabViewItem:overviewTab];
    panel.releasedWhenClosed = NO; panel.title = @"Animates Dev · Unity Playground";
    panel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [panel setFrameTopLeftPoint:NSMakePoint(NSMaxX(sceneWindow.frame)+8,NSMaxY(sceneWindow.frame))];
    [sceneWindow addChildWindow:panel ordered:NSWindowAbove];
    [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidResizeNotification object:sceneWindow queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        [panel setFrameTopLeftPoint:NSMakePoint(NSMaxX(sceneWindow.frame)+8,NSMaxY(sceneWindow.frame))];
    }];
    NSView *overviewContent=sidebar; sidebar=header;
    label(@"Animates Playground",20,73,530,23);
    status = label(@"Запуск оригинального Unity…",20,47,530,12);
    label(@"Персонаж",20,11,100,12);
    characterPicker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(126,9,424,28) pullsDown:NO];
    for (NSString *key in @[@"yuki",@"nixie",@"bot",@"raccoon",@"jareth",@"ani",@"mika"])
        if (catalog[key]) [characterPicker addItemWithTitle:catalog[key][@"displayName"] ?: catalog[key][@"sceneId"]];
    characterPicker.identifier = @"character"; characterPicker.target = self; characterPicker.action = @selector(action:);
    characterPicker.accessibilityLabel = @"Персонаж";
    [sidebar addSubview:characterPicker]; [loadControls addObject:characterPicker];
    sidebar=overviewContent;
    label(@"Эффекты и жесты",20,670,380,14);
    NSDictionary *names = @{@"hello":@"Привет",@"yes":@"Да",@"no":@"Нет",@"kiss":@"Поцелуй",@"peace":@"Peace",@"love":@"Любовь",@"excitement":@"Восторг",@"angry":@"Злость",@"sad":@"Грусть",@"popcorn":@"Попкорн",@"joystick":@"Геймпад",@"newspaper":@"Газета",@"phone":@"Телефон",@"typing":@"Печатает"};
    NSMutableOrderedSet *all = [NSMutableOrderedSet orderedSetWithArray:@[@"hello",@"yes",@"no",@"kiss",@"peace",@"love",@"excitement",@"angry",@"sad",@"popcorn",@"joystick",@"newspaper",@"phone",@"typing"]];
    for (NSString *key in [catalog.allKeys sortedArrayUsingSelector:@selector(compare:)])
        for (NSString *effect in catalog[key][@"effects"])
            if (![effect hasPrefix:@"stop_"] && ![effect isEqualToString:@"listening"]) [all addObject:effect];
    NSArray *ids = all.array;
    for (NSUInteger i=0;i<ids.count;i++) {
        NSButton *b = button(names[ids[i]] ?: ids[i],[@"effect:" stringByAppendingString:ids[i]],20,635,124,YES);
        [b setButtonType:NSButtonTypePushOnPushOff]; [effectButtons addObject:b];
    }
    label(@"Повторное нажатие выключает длительное действие",20,464,380,10);
    button(@"Остановить",@"stop",20,431,124,YES);
    listenToggle = button(@"Слушает",@"listening",150,431,124,YES); [listenToggle setButtonType:NSButtonTypeSwitch];
    fpsToggle = button(@"FPS",@"fps",280,431,110,YES); [fpsToggle setButtonType:NSButtonTypeSwitch];
    label(@"Камера",20,357,100,12);
    cameraPicker = picker(@"camera",355,@[@"0 · FollowCamera",@"1 · CloseCamera",@"2 · PIPCamera",@"3 · SPIPCamera",@"4 · BackgroundCamera",@"5 · HoloCamera"],274);
    label(@"Фон",20,320,100,12);
    backgroundPicker = picker(@"background",318,@[@"0 · Default Background",@"1 · TimeOfDay"],274);
    label(@"Непрозрачность окна",20,283,145,11);
    NSSlider *alpha = [NSSlider sliderWithValue:1 minValue:0 maxValue:1 target:self action:@selector(action:)];
    alpha.frame = NSMakeRect(170,283,224,24); alpha.identifier = @"alpha"; alpha.accessibilityLabel = @"Непрозрачность окна"; alphaSlider = alpha;
    [sidebar addSubview:alpha]; [sceneControls addObject:alpha];
    effectState = label(@"Эффекты: —",20,247,380,11);
    bodyState = label(@"Тело: —",20,225,380,11);
    faceState = label(@"Лицо: —",20,203,380,11);
    label(@"События",20,171,170,13);
    button(@"Полный лог ↗",@"logs",270,170,130,YES);
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20,20,380,140)];
    scroll.hasVerticalScroller = YES; scroll.borderType = NSBezelBorder;
    logView = [[NSTextView alloc] initWithFrame:scroll.bounds]; logView.editable = NO;
    logView.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
    logView.textContainerInset = NSMakeSize(8,8); scroll.documentView = logView; [sidebar addSubview:scroll];
    DevControlsAttach(tabs);
    [overview scrollPoint:NSMakePoint(0,MAX(0,710-sidebarScroll.contentSize.height))];
    sceneEnabled(NO);
    [panel orderFront:nil]; [sceneWindow makeKeyAndOrderFront:nil];
    record(@"Native bridge · оригинальное окно Unity");
}
@end

#define EXPORT __attribute__((visibility("default")))
#define REGISTER(name, variable, type) EXPORT void _Register##name##Callback(type callback) { variable = callback; }
typedef void (*LoadCB)(const char *, const char *);
typedef void (*VoidCB)(void);
typedef void (*EffectCB)(const char *, bool);
typedef void (*IntCB)(int32_t);
typedef void (*BoolCB)(bool);
typedef void (*FloatCB)(float);
REGISTER(LoadCharacter, loadCharacter, LoadCB)
REGISTER(UnloadCharacter, unloadCharacter, VoidCB)
REGISTER(PlayEffect, playEffect, EffectCB)
REGISTER(ChangeActiveCamera, changeCamera, IntCB)
REGISTER(ChangeActiveBackground, changeBackground, IntCB)
REGISTER(SetBackgroundAlpha, setBackgroundAlpha, FloatCB)
REGISTER(SetListening, setListening, BoolCB)
REGISTER(Interrupt, interrupt, VoidCB)
REGISTER(SetFrameTimeCounterVisible, setFPS, BoolCB)
REGISTER(ActivityAnimationsEnabled, setActivities, BoolCB)
// Streaming speech APIs are not driven by this local scene playground.
#define IGNORE(name) EXPORT void _Register##name##Callback(void *callback) { (void)callback; }
IGNORE(AppendAnimationData) IGNORE(AppendAudio) IGNORE(AppendBlendShapesData)
IGNORE(AppendInferenceSpeech) IGNORE(CompleteInferenceSpeech) IGNORE(GetCameraPosition)
IGNORE(GetSceneDownloadProgress) IGNORE(GetThreeFrames) IGNORE(GetTwoBlendShapesFrames)
IGNORE(GetUnityVersion) IGNORE(InterruptAndAppend) IGNORE(InterruptAndPlay)
IGNORE(InterruptInference) IGNORE(PlayCharacterSpeech) IGNORE(SetAssetBundlesURL)
IGNORE(UpdateGenerationSettings) IGNORE(UpdatePersonality) IGNORE(ActivityContext)
EXPORT void _CreateSwiftUIOverlay(void) { dispatch_async(dispatch_get_main_queue(), ^{ controller = [Playground new]; [controller build]; }); }
EXPORT void _DestroySwiftUIOverlay(void) {}
EXPORT void _NotifyStartSceneLoaded(void) {
    record(@"← StartSceneLoaded");
    dispatch_async(dispatch_get_main_queue(), ^{
        ready = true;
        NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:@"PlaygroundCharacter"];
        load(catalog[saved ?: @""] ? saved : @"yuki");
    });
}
EXPORT void _NotifyCharacterLoaded(const char *name) {
    NSString *value = name ? @(name) : @""; record([@"← CharacterLoaded " stringByAppendingString:value]);
    dispatch_async(dispatch_get_main_queue(), ^{
        nativeScene=value;
        static dispatch_once_t metadataOnce;
        dispatch_once(&metadataOnce, ^{ DevDumpMetadata(); });
        character = value.lowercaseString;
        DevRuntimeSnapshot();
        DevControlsRefresh(value, catalog[character]);
        sceneEnabled(YES);
        status.stringValue = [@"● Unity 6 · " stringByAppendingString:value];
        [cameraPicker selectItemAtIndex:selectedCamera]; [backgroundPicker selectItemAtIndex:selectedBackground];
        listenToggle.state = NSControlStateValueOff;
        fpsToggle.state = NSControlStateValueOff; if (setFPS) setFPS(false);
        alphaSlider.doubleValue = 1;
        if (setBackgroundAlpha) setBackgroundAlpha(1);
    });
}
EXPORT void _NotifyCharacterLoadingFailed(const char *name, const char *error) {
    record([NSString stringWithFormat:@"← LoadFailed %s: %s",name?name:"",error?error:""]);
    dispatch_async(dispatch_get_main_queue(), ^{ status.stringValue = @"Не удалось загрузить сцену — см. журнал"; sceneEnabled(NO); });
}
EXPORT void _NotifyCharacterUnloaded(void) {
    record(@"← CharacterUnloaded");
    dispatch_async(dispatch_get_main_queue(), ^{
        nativeScene=nil;
        if(pendingScene){NSString *name=pendingScene,*config=pendingConfig;pendingScene=nil;pendingConfig=nil;loadCharacter(name.UTF8String,config.UTF8String);}
    });
}
EXPORT void _NotifySceneVisualStateChanged(const char *json) {
    NSString *raw = json ? @(json) : @"{}";
    fprintf(stderr, "[PlaygroundState] %s\n", raw.UTF8String);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *s = [NSJSONSerialization JSONObjectWithData:[raw dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if (![s isKindOfClass:NSDictionary.class]) return;
        NSArray *allEffects = [(s[@"activeAnimatorEffects"] ?: @[]) arrayByAddingObjectsFromArray:s[@"otherActiveEffects"] ?: @[]];
        activeEffects = [NSSet setWithArray:allEffects];
        effectState.stringValue = [@"Эффекты: " stringByAppendingString:stateText(allEffects)];
        bodyState.stringValue = [@"Тело: " stringByAppendingString:stateText(s[@"activeBodyAnimationStates"])];
        faceState.stringValue = [@"Лицо: " stringByAppendingString:stateText(s[@"activeFaceAnimationStates"])];
        for (NSButton *b in effectButtons) b.state = [activeEffects containsObject:[b.identifier substringFromIndex:7]] ? NSControlStateValueOn : NSControlStateValueOff;
        record([NSString stringWithFormat:@"← %@ · %@", stateText(s[@"activeBodyAnimationStates"]), stateText(s[@"activeFaceAnimationStates"])]);
    });
}
EXPORT void _NotifyAnimationIsComplete(void) { record(@"← AnimationComplete"); }
EXPORT void _NotifyEngineAudioIsComplete(void) { record(@"← AudioComplete"); }
EXPORT void _NotifyCharacterSpeechIsCompleted(void) { record(@"← SpeechComplete"); }
EXPORT void _NotifyCharacterSpeechInterrupted(void) { record(@"← SpeechInterrupted"); }
EXPORT void _NotifyInferenceAudioBatch(const float *audio, int32_t length, bool first) { DevAudioBatch(audio,length,first); }
EXPORT void _NotifyInferenceAudioInterrupt(void) { DevAudioInterrupt(); }
EXPORT void _StartActivityDetection(void) {}
EXPORT void _StopActivityDetection(void) {}

// Original inference calls these analytics hooks. Keep the ABI and record locally.
EXPORT void _sendStartLinkedTransaction(const char *id,const char *name,const char *operation,const char *group) {
    fprintf(stderr,"[DevTrace] begin %s %s\n",name?name:"",operation?operation:"");
}
EXPORT void _sendSetTransactionTag(const char *id,const char *key,const char *value) {}
EXPORT void _sendSetTransactionMeasurement(const char *id,const char *key,double value) {}
EXPORT void _sendFinishTransaction(const char *id,int32_t status) {fprintf(stderr,"[DevTrace] finish %d\n",status);}
EXPORT void _sendCancelTransaction(const char *id) {fprintf(stderr,"[DevTrace] cancel\n");}
