#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
extern NSDictionary *DevRuntimeSnapshot(void);
extern NSString *DevRuntimeCommand(NSString *,NSArray *);
extern int DevRuntimeSampleRate(void);
extern NSString *DevRuntimeSpeech(NSData *);
extern NSString *DevRuntimeFace(NSDictionary *);

static NSWindow *window;
static NSString *sceneName;
static NSDictionary *entry;
static NSTabView *allTabs;
static NSMutableArray<NSTextField *> *resultLabels;
static NSTextField *resultLabel,*currentLabel;
static NSPopUpButton *outfits,*hairs,*states;
static NSSlider *hue,*saturation,*brightness,*intensity;
static NSMutableArray<NSButton *> *params;
static NSMutableArray<NSTextField *> *settings;
static NSMutableDictionary<NSString *,NSSlider *> *faceSliders;
static AVAudioEngine *audioEngine;
static AVAudioPlayerNode *audioNode;
static NSData *speechData;

@interface DevOptions : NSObject
- (void)action:(NSControl *)sender;
- (void)build;
- (void)refresh;
@end
static DevOptions *options;

static NSTextField *Text(NSView *v,NSString *s,CGFloat y,CGFloat size) {
    NSTextField *t=[NSTextField labelWithString:s];t.frame=NSMakeRect(20,y,510,26);t.font=[NSFont systemFontOfSize:size];[v addSubview:t];return t;
}
static NSButton *Button(NSView *v,NSString *title,NSString *cmd,CGFloat x,CGFloat y,CGFloat w) {
    NSButton *b=[NSButton buttonWithTitle:title target:options action:@selector(action:)];b.identifier=cmd;b.frame=NSMakeRect(x,y,w,30);b.bezelStyle=NSBezelStyleRounded;[v addSubview:b];return b;
}
static NSPopUpButton *Picker(NSView *v,NSArray *items,NSString *label,CGFloat y) {
    Text(v,label,y+29,12);NSPopUpButton *p=[[NSPopUpButton alloc]initWithFrame:NSMakeRect(20,y,365,28) pullsDown:NO];[p addItemsWithTitles:items];p.accessibilityLabel=label;[v addSubview:p];return p;
}
static NSSlider *Slider(NSView *v,NSString *title,NSString *cmd,CGFloat y,double value,double min,double max) {
    NSTextField *label=Text(v,title,y,12);label.frame=NSMakeRect(20,y,160,24);
    NSSlider *s=[NSSlider sliderWithValue:value minValue:min maxValue:max target:options action:@selector(action:)];s.identifier=cmd;s.accessibilityLabel=title;s.frame=NSMakeRect(185,y,340,24);[v addSubview:s];return s;
}
static void ShowResult(NSString *error,NSString *success) {for(NSTextField *label in resultLabels){label.stringValue=error?:success;label.toolTip=error?:success;}}
static NSView *Tab(NSTabView *tabs,NSString *title) {
    NSTabViewItem *item=[[NSTabViewItem alloc]initWithIdentifier:title];item.label=title;
    NSScrollView *scroll=[[NSScrollView alloc]initWithFrame:NSMakeRect(0,0,550,620)];scroll.hasVerticalScroller=YES;scroll.autohidesScrollers=YES;
    NSView *v=[[NSView alloc]initWithFrame:NSMakeRect(0,0,550,620)];scroll.documentView=v;item.view=scroll;[tabs addTabViewItem:item];
    NSTextField *status=Text(v,@"",5,11);[resultLabels addObject:status];return v;
}

void DevAudioInterrupt(void) {dispatch_async(dispatch_get_main_queue(), ^{[audioNode stop];});}
void DevAudioBatch(const float *samples,int count,bool first) {
    if(!samples||count<=0)return;NSData *data=[NSData dataWithBytes:samples length:(NSUInteger)count*sizeof(float)];
    dispatch_async(dispatch_get_main_queue(), ^{
        int rate=DevRuntimeSampleRate();if(rate<=0)return;
        AVAudioFormat *format=[[AVAudioFormat alloc]initStandardFormatWithSampleRate:rate channels:1];
        if(!audioEngine){audioEngine=[AVAudioEngine new];audioNode=[AVAudioPlayerNode new];[audioEngine attachNode:audioNode];[audioEngine connect:audioNode to:audioEngine.mainMixerNode format:format];}
        if(first)[audioNode stop];NSError *e=nil;if(!audioEngine.isRunning)[audioEngine startAndReturnError:&e];
        if(e){ShowResult(e.localizedDescription,nil);return;}
        AVAudioPCMBuffer *buffer=[[AVAudioPCMBuffer alloc]initWithPCMFormat:format frameCapacity:count];buffer.frameLength=count;memcpy(buffer.floatChannelData[0],data.bytes,data.length);
        [audioNode scheduleBuffer:buffer completionHandler:nil];if(!audioNode.isPlaying)[audioNode play];
    });
}

@implementation DevOptions
- (void)refresh {
    NSDictionary *s=DevRuntimeSnapshot();
    currentLabel.stringValue=[NSString stringWithFormat:@"Костюм: %@\nВолосы: %@",s[@"outfit"]?:@"—",s[@"hair"]?:@"—"];
    currentLabel.toolTip=currentLabel.stringValue;
    for(NSButton *b in params)b.state=[s[@"activeParams"] containsObject:[b.identifier substringFromIndex:6]]?NSControlStateValueOn:NSControlStateValueOff;
    for(NSSlider *slider in @[hue,saturation,brightness,intensity])slider.enabled=[s[@"hairColorAvailable"] boolValue];
}
- (void)action:(NSControl *)sender {
    NSString *cmd=sender.identifier;NSString *error=nil;
    if([cmd isEqualToString:@"refresh"]){[self refresh];return;}
    if([cmd hasPrefix:@"face:"]) {
        NSString *test=[cmd substringFromIndex:5];
        if(![test isEqual:@"channel"]&&![test isEqual:@"play"]){
            for(NSSlider *s in faceSliders.allValues)s.doubleValue=0;
            NSArray *channels=[test isEqual:@"smile"]?@[@"MouthSmileLeft",@"MouthSmileRight"]:[test isEqual:@"blink"]?@[@"EyeBlinkLeft",@"EyeBlinkRight"]:[test isEqual:@"jaw"]?@[@"JawOpen"]:@[];
            for(NSString *name in channels)faceSliders[name].doubleValue=1;
        }
        NSMutableDictionary *weights=[NSMutableDictionary new];for(NSString *name in faceSliders)if(faceSliders[name].doubleValue>0)weights[name]=@(faceSliders[name].doubleValue);
        error=DevRuntimeFace([test isEqual:@"reset"]?nil:weights);ShowResult(error,[test isEqual:@"reset"]?@"Возврат к автоматической мимике":@"Выражение запущено на 5 секунд");return;
    }
    if([cmd isEqualToString:@"outfit"]||[cmd isEqualToString:@"hair"]){BOOL cloth=[cmd isEqualToString:@"outfit"];NSPopUpButton *p=cloth?outfits:hairs;NSArray *items=entry[@"wardrobe"][cloth?@"outfits":@"hairs"];if(p.indexOfSelectedItem<0)return;NSDictionary *item=items[p.indexOfSelectedItem]; if([item[@"available"] isEqual:@NO]){ShowResult(item[@"reason"],nil);return;}error=DevRuntimeCommand(cmd,@[item[@"id"]]);}
    else if([cmd isEqualToString:@"hairColor"]){error=DevRuntimeCommand(cmd,@[@(hue.doubleValue),@(saturation.doubleValue),@(brightness.doubleValue),@(intensity.doubleValue)]);}
    else if([cmd hasPrefix:@"param:"]){error=DevRuntimeCommand(@"parameter",@[[cmd substringFromIndex:6],@(((NSButton *)sender).state==NSControlStateValueOn)]);}
    else if([cmd isEqualToString:@"state"]){if(states.indexOfSelectedItem<0)return;error=DevRuntimeCommand(cmd,@[states.titleOfSelectedItem]);}
    else if([cmd isEqualToString:@"settings"]){NSMutableArray *v=[NSMutableArray new];for(NSTextField *t in settings)[v addObject:@(t.intValue)];if([v[0] intValue]<1||[v[1] intValue]<1||[v[0] intValue]>100||[v[1] intValue]>100){ShowResult(@"Число шагов должно быть от 1 до 100",nil);return;}error=DevRuntimeCommand(cmd,v);}
    else if([@[@"danceSpeed",@"distance",@"viewYaw",@"SetReviewProgress"] containsObject:cmd])error=DevRuntimeCommand(cmd,@[@(sender.floatValue)]);
    else if([cmd isEqualToString:@"rbf"])error=DevRuntimeCommand(cmd,@[@(((NSButton *)sender).state==NSControlStateValueOn)]);
    else if([cmd isEqualToString:@"audio"]){
        NSOpenPanel *p=[NSOpenPanel openPanel];p.canChooseDirectories=NO;p.allowsMultipleSelection=NO;p.allowedFileTypes=@[@"wav",@"aiff",@"aif",@"mp3",@"m4a"];p.message=@"Локальный аудиофайл для генерации речи и мимики";
        [p beginSheetModalForWindow:window completionHandler:^(NSModalResponse response){
            if(response!=NSModalResponseOK)return;NSError *e=nil;AVAudioFile *file=[[AVAudioFile alloc]initForReading:p.URL error:&e];int rate=DevRuntimeSampleRate();
            if(!file||rate<=0){ShowResult(e.localizedDescription?:@"Движок не сообщил частоту аудио",nil);return;}
            if(file.length>file.processingFormat.sampleRate*60){ShowResult(@"Для одного теста выбери запись до 60 секунд",nil);return;}
            AVAudioPCMBuffer *input=[[AVAudioPCMBuffer alloc]initWithPCMFormat:file.processingFormat frameCapacity:(AVAudioFrameCount)file.length];if(![file readIntoBuffer:input error:&e]){ShowResult(e.localizedDescription,nil);return;}
            AVAudioFormat *format=[[AVAudioFormat alloc]initStandardFormatWithSampleRate:rate channels:1];AVAudioConverter *converter=[[AVAudioConverter alloc]initFromFormat:input.format toFormat:format];
            AVAudioPCMBuffer *output=[[AVAudioPCMBuffer alloc]initWithPCMFormat:format frameCapacity:(AVAudioFrameCount)(input.frameLength*rate/input.format.sampleRate+256)];__block BOOL sent=NO;
            [converter convertToBuffer:output error:&e withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount n,AVAudioConverterInputStatus *status){if(sent){*status=AVAudioConverterInputStatus_EndOfStream;return nil;}sent=YES;*status=AVAudioConverterInputStatus_HaveData;return input;}];
            if(e){ShowResult(e.localizedDescription,nil);return;}speechData=[NSData dataWithBytes:output.floatChannelData[0] length:output.frameLength*sizeof(float)];
            NSString *err=DevRuntimeSpeech(speechData);ShowResult(err,[NSString stringWithFormat:@"Речь отправлена: %@ · %.1f с",p.URL.lastPathComponent,(double)output.frameLength/rate]);
        }];return;
    } else error=DevRuntimeCommand(cmd,@[]);
    ShowResult(error,@"Команда отправлена в Unity");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,800*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self refresh];});
}
- (void)build {
    id selected=allTabs.selectedTabViewItem.identifier;
    for(NSTabViewItem *item in allTabs.tabViewItems.copy)if(![item.identifier isEqual:@"effects"])[allTabs removeTabViewItem:item];
    resultLabels=[NSMutableArray new];NSTabView *tabs=allTabs;
    NSView *wardrobe=Tab(tabs,@"Образ");
    currentLabel=Text(wardrobe,@"",58,10);currentLabel.frame=NSMakeRect(20,55,510,50);currentLabel.maximumNumberOfLines=2;
    NSMutableArray *names=[NSMutableArray new];for(NSDictionary *x in entry[@"wardrobe"][@"outfits"])[names addObject:[x[@"available"] isEqual:@NO]?[x[@"name"] stringByAppendingString:@" · нет ресурса"]:x[@"name"]];
    outfits=Picker(wardrobe,names,@"Костюм",530);Button(wardrobe,@"Применить",@"outfit",400,530,125);
    names=[NSMutableArray new];for(NSDictionary *x in entry[@"wardrobe"][@"hairs"])[names addObject:[x[@"available"] isEqual:@NO]?[x[@"name"] stringByAppendingString:@" · нет ресурса"]:x[@"name"]];
    hairs=Picker(wardrobe,names,@"Причёска",450);NSButton *hairButton=Button(wardrobe,@"Применить",@"hair",400,450,125);hairButton.enabled=names.count>0;hairs.enabled=hairButton.enabled;
    hue=Slider(wardrobe,@"Оттенок волос",@"hairColor",360,0,0,1);saturation=Slider(wardrobe,@"Насыщенность",@"hairColor",320,0,0,1);brightness=Slider(wardrobe,@"Яркость",@"hairColor",280,1,0,1);intensity=Slider(wardrobe,@"Интенсивность",@"hairColor",240,0,0,4);
    Text(wardrobe,@"Цвет доступен только при наличии штатного контроллера.",190,11);
    Text(wardrobe,[NSString stringWithFormat:@"В исходной сцене: костюмов — %lu, причёсок — %lu.",(unsigned long)[entry[@"wardrobe"][@"outfits"] count],(unsigned long)[entry[@"wardrobe"][@"hairs"] count]],155,11);
    NSView *animations=Tab(tabs,@"Движения");states=Picker(animations,entry[@"animatorStates"]?:@[],@"Состояние Animator",530);Button(animations,@"Запустить",@"state",400,530,125);
    Text(animations,@"Параметры персонажа",480,14);params=[NSMutableArray new];
    NSUInteger i=0;NSDictionary *snap=DevRuntimeSnapshot();
    for(NSString *p in snap[@"params"]){NSButton *b=Button(animations,p,[@"param:" stringByAppendingString:p],20+(i%3)*170,440-(i/3)*32,166);[b setButtonType:NSButtonTypeSwitch];[params addObject:b];i++;}
    Slider(animations,@"Скорость танца",@"danceSpeed",135,1,0.25,2);Button(animations,@"Сбросить параметры",@"resetAnimator",20,88,235);
    NSView *face=Tab(tabs,@"Мимика");NSArray *channels=snap[@"faceChannels"]?:@[];faceSliders=[NSMutableDictionary new];
    CGFloat faceHeight=MAX(620,200+channels.count*35);[face setFrameSize:NSMakeSize(550,faceHeight)];
    Text(face,[NSString stringWithFormat:@"Мимика · %lu каналов оригинальной модели",(unsigned long)channels.count],faceHeight-44,16);
    Text(face,@"Ползунки запускают выражение на 5 секунд.",faceHeight-74,12);
    Button(face,@"Улыбка",@"face:smile",20,faceHeight-113,125);Button(face,@"Моргание",@"face:blink",150,faceHeight-113,125);
    Button(face,@"Открыть рот",@"face:jaw",280,faceHeight-113,125);Button(face,@"Сброс",@"face:reset",410,faceHeight-113,115);
    Button(face,@"Повторить выражение",@"face:play",20,faceHeight-151,505);
    NSUInteger fi=0;for(NSDictionary *channel in channels){NSSlider *s=Slider(face,channel[@"name"],@"face:channel",faceHeight-192-fi*35,0,0,1);s.toolTip=channel[@"meshName"];faceSliders[channel[@"name"]]=s;fi++;}
    [face scrollPoint:NSMakePoint(0,faceHeight-((NSScrollView *)face.enclosingScrollView).contentSize.height)];
    NSView *speech=Tab(tabs,@"Речь");Text(speech,@"Речь и мимика из локального аудио",558,17);
    Text(speech,@"Оригинальный движок обрабатывает запись на этом Mac.",520,12);
    Button(speech,@"Выбрать аудиофайл…",@"audio",20,463,270);Button(speech,@"Прервать",@"InterruptInference",305,463,215);
    Text(speech,@"Параметры генерации",399,15);settings=[NSMutableArray new];
    NSArray *labels=@[@"Шаги тела",@"Шаги лица",@"Стиль тела",@"Стиль лица"],*keys=@[@"bodyDenoiseSteps",@"faceDenoiseSteps",@"animationStyle",@"faceAnimationStyle"];
    for(NSUInteger j=0;j<4;j++){CGFloat y=355-j*40;NSTextField *label=Text(speech,labels[j],y,12);label.frame=NSMakeRect(20,y,210,24);NSTextField *t=[[NSTextField alloc]initWithFrame:NSMakeRect(240,y,120,25)];t.intValue=[(entry[@"animationConfig"]?:snap[@"generationSettings"])[keys[j]] intValue];t.accessibilityLabel=labels[j];[speech addSubview:t];[settings addObject:t];}
    Button(speech,@"Применить параметры",@"settings",20,167,340);
    NSView *scene=Tab(tabs,@"Сцена");Slider(scene,@"Дистанция камеры",@"distance",540,0.5,0,1);
    Slider(scene,@"Ракурс персонажа",@"viewYaw",475,0,-90,90);
    Text(scene,@"Повтор движений",415,16);
    Button(scene,@"Открыть повтор",@"StartReview",20,363,240);Button(scene,@"Выйти из повтора",@"StopReview",280,363,240);
    Button(scene,@"Воспроизвести",@"PlayReview",20,315,240);Button(scene,@"Пауза",@"PauseReview",280,315,240);
    Slider(scene,@"Позиция повтора",@"SetReviewProgress",260,0,0,1);
    Button(wardrobe,@"Обновить состояние",@"refresh",20,110,250);[self refresh];
    if(selected)[allTabs selectTabViewItemWithIdentifier:selected];
}
@end

void DevControlsRefresh(NSString *name,NSDictionary *catalogEntry) {sceneName=name;entry=catalogEntry;if(allTabs)[options build];}
void DevControlsAttach(NSTabView *tabs) {
    if(!options)options=[DevOptions new];allTabs=tabs;window=tabs.window;
    if(entry)[options build];
}
void DevControlsShow(void) {
    if(!allTabs)return;
    [allTabs selectTabViewItemWithIdentifier:@"Образ"];
    [window makeKeyAndOrderFront:nil];
}
