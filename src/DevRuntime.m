#import <Foundation/Foundation.h>
#import <dlfcn.h>

// Resolve metadata through Unity's exported IL2CPP API, never binary offsets.
void DevDumpMetadata(void) {
    void *lib=dlopen([[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/Frameworks/GameAssembly.dylib"] UTF8String],RTLD_LAZY|RTLD_NOLOAD);
    if(!lib)return;
#define API(ret,name,args) ret (*name)args=dlsym(lib,"il2cpp_" #name); if(!name)return
    API(void *,domain_get,(void));
    API(void **,domain_get_assemblies,(void *,size_t *));
    API(void *,assembly_get_image,(void *));
    API(const char *,image_get_name,(void *));
    API(size_t,image_get_class_count,(void *));
    API(void *,image_get_class,(void *,size_t));
    API(const char *,class_get_name,(void *));
    API(const char *,class_get_namespace,(void *));
    API(void *,class_get_parent,(void *));
    API(void *,class_get_fields,(void *,void **));
    API(const char *,field_get_name,(void *));
    API(void *,field_get_type,(void *));
    API(unsigned,field_get_flags,(void *));
    API(char *,type_get_name,(void *));
    API(void,free,(void *));
    API(void *,class_get_methods,(void *,void **));
    API(const char *,method_get_name,(void *));
    API(uint32_t,method_get_param_count,(void *));
    API(void *,method_get_param,(void *,uint32_t));
    API(const char *,method_get_param_name,(void *,uint32_t));
    API(void *,method_get_return_type,(void *));
    API(uint32_t,method_get_flags,(void *,uint32_t *));
    NSMutableArray *result=[NSMutableArray new];
    size_t count=0;void **assemblies=domain_get_assemblies(domain_get(),&count);
    for(size_t i=0;i<count;i++) {
        void *im=assembly_get_image(assemblies[i]);
        for(size_t j=0;j<image_get_class_count(im);j++) {
            void *c=image_get_class(im,j),*parent=class_get_parent(c),*it=NULL,*f;
            NSString *className=@(class_get_name(c));
            if(strcmp(image_get_name(im),"Assembly-CSharp.dll") && ![className containsString:@"Animat"] && ![className containsString:@"Emotion"] && ![className containsString:@"Generation"] && ![className containsString:@"Dance"]) continue;
            if([className hasPrefix:@"<"] || [className containsString:@"Debug"] || [className containsString:@"Formatter"])continue;
            NSMutableArray *fields=[NSMutableArray new],*methods=[NSMutableArray new];
            while((f=class_get_fields(c,&it))) {
                char *t=type_get_name(field_get_type(f));
                [fields addObject:@{@"name":@(field_get_name(f)),@"type":@(t),@"flags":@(field_get_flags(f))}];free(t);
            }
            it=NULL;
            while((f=class_get_methods(c,&it))) {
                NSMutableArray *params=[NSMutableArray new];
                for(uint32_t k=0;k<method_get_param_count(f);k++) {
                    char *t=type_get_name(method_get_param(f,k));const char *n=method_get_param_name(f,k);
                    [params addObject:@{@"name":n?@(n):@"",@"type":@(t)}];free(t);
                }
                char *t=type_get_name(method_get_return_type(f));uint32_t impl;
                [methods addObject:@{@"name":@(method_get_name(f)),@"return":@(t),@"flags":@(method_get_flags(f,&impl)),@"params":params}];free(t);
            }
            [result addObject:@{@"name":@(class_get_name(c)),@"assembly":@(image_get_name(im)),@"namespace":@(class_get_namespace(c)),@"parent":parent?@(class_get_name(parent)):@"",@"fields":fields,@"methods":methods}];
        }
    }
    NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/AnimatesDev/runtime-metadata.json"];
    [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil] writeToFile:path atomically:YES];
    fprintf(stderr,"[DevRuntime] Metadata: %lu classes\n",(unsigned long)result.count);
}

static void *rt;
#define RT(ret,n,args) static ret (*r_##n)args
RT(void *,domain_get,(void)); RT(void **,domain_get_assemblies,(void *,size_t *)); RT(void *,assembly_get_image,(void *));
RT(size_t,image_get_class_count,(void *)); RT(void *,image_get_class,(void *,size_t)); RT(const char *,class_get_name,(void *));
RT(void *,class_get_parent,(void *)); RT(void *,object_get_class,(void *)); RT(void *,class_get_field_from_name,(void *,const char *));
RT(void *,field_get_value_object,(void *,void *)); RT(void *,class_get_methods,(void *,void **)); RT(const char *,method_get_name,(void *));
RT(uint32_t,method_get_param_count,(void *)); RT(void *,method_get_param,(void *,uint32_t)); RT(char *,type_get_name,(void *)); RT(void,free,(void *));
RT(void *,runtime_invoke,(void *,void *,void **,void **)); RT(void *,object_unbox,(void *));
RT(void *,string_new,(const char *)); RT(int32_t,string_length,(void *)); RT(const unichar *,string_chars,(void *));
RT(void,format_exception,(void *,char *,int));
RT(void *,class_get_fields,(void *,void **)); RT(const char *,field_get_name,(void *));
static NSMutableDictionary *classes;
static BOOL RInit(void) {
    if(classes)return YES;
    rt=dlopen([[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/Frameworks/GameAssembly.dylib"] UTF8String],RTLD_LAZY|RTLD_NOLOAD);if(!rt)return NO;
#define LOAD(n) r_##n=dlsym(rt,"il2cpp_" #n); if(!r_##n)return NO
    LOAD(domain_get);LOAD(domain_get_assemblies);LOAD(assembly_get_image);LOAD(image_get_class_count);LOAD(image_get_class);LOAD(class_get_name);
    LOAD(class_get_parent);LOAD(object_get_class);LOAD(class_get_field_from_name);LOAD(field_get_value_object);LOAD(class_get_methods);LOAD(method_get_name);
    LOAD(method_get_param_count);LOAD(method_get_param);LOAD(type_get_name);LOAD(free);LOAD(runtime_invoke);LOAD(object_unbox);LOAD(string_new);LOAD(string_length);LOAD(string_chars);LOAD(format_exception);
    LOAD(class_get_fields);LOAD(field_get_name);
    classes=[NSMutableDictionary new];size_t count=0;void **all=r_domain_get_assemblies(r_domain_get(),&count);
    for(size_t i=0;i<count;i++){void *im=r_assembly_get_image(all[i]);for(size_t j=0;j<r_image_get_class_count(im);j++){void *c=r_image_get_class(im,j);NSString *n=@(r_class_get_name(c));if(!classes[n])classes[n]=[NSValue valueWithPointer:c];}}
    return YES;
}
static void *RC(NSString *name){return [classes[name] pointerValue];}
static void *RF(void *obj,const char *name){if(!obj)return NULL;void *f=r_class_get_field_from_name(r_object_get_class(obj),name);return f?r_field_get_value_object(f,obj):NULL;}
static void *RS(NSString *cls,const char *name){void *c=RC(cls);if(!c)return NULL;void *f=r_class_get_field_from_name(c,name);return f?r_field_get_value_object(f,NULL):NULL;}
static NSString *RString(void *obj){return obj?[[NSString alloc] initWithCharacters:r_string_chars(obj) length:r_string_length(obj)]:@"";}
static NSString *RType(void *t){char *n=r_type_get_name(t);NSString *s=@(n);r_free(n);return s;}
static void *RM(void *c,NSString *name,NSArray *types){for(;c;c=r_class_get_parent(c)){void *it=NULL,*m;while((m=r_class_get_methods(c,&it))){if(name && ![name isEqualToString:@(r_method_get_name(m))])continue;if(r_method_get_param_count(m)!=types.count)continue;BOOL match=YES;for(NSUInteger i=0;i<types.count;i++)if(![RType(r_method_get_param(m,(uint32_t)i)) isEqualToString:types[i]])match=NO;if(match)return m;}}return NULL;}
static void *RI(void *c,void *obj,NSString *method,NSArray *types,void **args,NSString **error){void *m=RM(c,method,types);if(!m){if(error)*error=[@"Метод недоступен: " stringByAppendingString:method];return NULL;}void *ex=NULL;void *v=r_runtime_invoke(m,obj,args,&ex);if(ex){char b[2048]={0};r_format_exception(ex,b,sizeof(b));if(error)*error=@(b);fprintf(stderr,"[DevRuntime] %s\n",b);return NULL;}return v;}
static void *RCall(void *obj,NSString *method,NSArray *types,void **args){return obj?RI(r_object_get_class(obj),obj,method,types,args,NULL):NULL;}
static int RInt(void *v){return v?*(int32_t *)r_object_unbox(v):0;}
static float RFloat(void *v){return v?*(float *)r_object_unbox(v):0;}
static BOOL RBool(void *v){return v?*(bool *)r_object_unbox(v):NO;}
static void *RScene(void){return RF(RS(@"SceneLoop","INSTANCE"),"sceneData");}
static void *RCharacter(void){return RF(RScene(),"characterData");}
static void *RAnimation(void){return RF(RCharacter(),"animationData");}
static NSArray *RList(void *list,NSString *(^value)(void *)){if(!list)return @[];NSMutableArray *items=[NSMutableArray new];int n=RInt(RCall(list,@"get_Count",@[],NULL));for(int i=0;i<MIN(n,256);i++){void *args[]={&i};void *item=RCall(list,@"get_Item",@[@"System.Int32"],args);if(item)[items addObject:value(item)?:@""];}return items;}
static NSArray *RFaceChannels(void) {
    void *anim=RAnimation(),*face=RF(anim,"face"),*mapping=RF(anim,"blendShapeMapping");
    if(!face||!RBool(RF(anim,"animateBlendShapes")))return @[];
    void *mesh=RCall(face,@"get_sharedMesh",@[],NULL);int count=RInt(RCall(mesh,@"get_blendShapeCount",@[],NULL));
    int mapped=RInt(RCall(mapping,@"get_Count",@[],NULL));NSMutableArray *channels=[NSMutableArray new];void *it=NULL,*field;
    while((field=r_class_get_fields(RC(@"BlendShapeType"),&it))) {
        const char *name=r_field_get_name(field);if(!strcmp(name,"value__"))continue;
        int index=RInt(RS(@"BlendShapeType",name));if(index<0||index>=mapped)continue;
        void *a[]={&index};int meshIndex=RInt(RCall(mapping,@"get_Item",@[@"System.Int32"],a));if(meshIndex<0||meshIndex>=count)continue;
        void *ma[]={&meshIndex};NSString *meshName=RString(RCall(mesh,@"GetBlendShapeName",@[@"System.Int32"],ma));
        [channels addObject:@{@"name":@(name),@"index":@(index),@"meshIndex":@(meshIndex),@"meshName":meshName}];
    }
    return channels;
}
NSDictionary *DevRuntimeSnapshot(void) {
    if(!RInit()||!RScene())return @{};
    void *ch=RCharacter(),*anim=RAnimation(),*wardrobe=RF(ch,"characterOutfitData"),*states=RF(anim,"animatorStatesData");
    NSMutableDictionary *out=[NSMutableDictionary new];
    out[@"outfit"]=RString(RF(RF(RF(wardrobe,"dressedOutfit"),"outfit"),"id"));
    out[@"hair"]=RString(RF(RF(RF(wardrobe,"dressedHair"),"outfit"),"id"));
    out[@"params"]=RList(RF(states,"animatorBoolParams"),^NSString *(void *o){return RString(RF(o,"id"));});
    out[@"states"]=RList(RF(states,"animatorStateEntries"),^NSString *(void *o){return RString(RF(o,"id"));});
    void *settings=RF(anim,"generationSettings");
    out[@"settingsClass"]=settings?@(r_class_get_name(r_object_get_class(settings))):@"";
    out[@"statesClass"]=states?@(r_class_get_name(r_object_get_class(states))):@"";
    out[@"hairColorAvailable"]=@(RF(RF(wardrobe,"dressedHair"),"outfitColorController")!=NULL);
    void *config=RF(RF(RS(@"NativeApp","INSTANCE"),"animationGenerationSettings"),"modelSettings_3_0");
    if(config) out[@"generationSettings"]=@{@"bodyDenoiseSteps":@(RInt(RF(config,"bodyDenoiseSteps"))),@"faceDenoiseSteps":@(RInt(RF(config,"faceDenoiseSteps"))),@"animationStyle":@(RInt(RF(config,"animationStyle"))),@"faceAnimationStyle":@(RInt(RF(config,"faceAnimationStyle")))};
    else {void *defaults=RI(RC(@"AnimationGenerationConfig"),NULL,@"get_Default",@[],NULL,NULL);out[@"generationSettings"]=@{@"bodyDenoiseSteps":@(RInt(RF(defaults,"bodyDenoiseSteps"))),@"faceDenoiseSteps":@(RInt(RF(defaults,"faceDenoiseSteps"))),@"animationStyle":@(RInt(RF(defaults,"bodyStyle"))),@"faceAnimationStyle":@(RInt(RF(defaults,"faceStyle")))};}
    NSMutableArray *active=[NSMutableArray new];
    void *activeSet=RF(states,"activeBoolParams");
    for(NSString *name in out[@"params"]) {void *str=r_string_new(name.UTF8String);void *a[]={str};if(RBool(RCall(activeSet,@"Contains",@[@"System.String"],a)))[active addObject:name];}
    out[@"activeParams"]=active;
    out[@"faceChannels"]=RFaceChannels();
    NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/AnimatesDev/runtime-scene.json"];
    [[NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingPrettyPrinted error:nil] writeToFile:path atomically:YES];
    static NSDictionary *previous;
    if(![previous isEqualToDictionary:out]) fprintf(stderr,"[DevRuntime] Scene %s\n",[[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:out options:0 error:nil] encoding:NSUTF8StringEncoding] UTF8String]);
    previous=[out copy];
    return out;
}

NSString *DevRuntimeCommand(NSString *command, NSArray *values) {
    if(!RInit()||!RScene())return @"Сцена не загружена";
    NSString *error=nil;void *states=RF(RAnimation(),"animatorStatesData");
    if([command isEqualToString:@"outfit"] || [command isEqualToString:@"hair"]) {
        NSString *id=values.firstObject;const char *p=id.UTF8String;bool hide=false;void *args[]={&p,&hide};
        RI(RC(@"WardrobeNativeApiDelegateImpl"),NULL,[command isEqualToString:@"outfit"]?@"ChangeCloth":@"ChangeHair",[command isEqualToString:@"outfit"]?@[@"System.IntPtr",@"System.Boolean"]:@[@"System.IntPtr"],args,&error);
    } else if([command isEqualToString:@"hairColor"]) {
        float h=[values[0] floatValue],s=[values[1] floatValue],v=[values[2] floatValue],intensity=[values[3] floatValue];void *args[]={&h,&s,&v,&intensity};
        RI(RC(@"WardrobeNativeApiDelegateImpl"),NULL,@"ChangeHairColor",@[@"System.Single",@"System.Single",@"System.Single",@"System.Single"],args,&error);
    } else if([command isEqualToString:@"parameter"]) {
        void *str=r_string_new([values[0] UTF8String]);bool value=[values[1] boolValue];void *args[]={states,str,&value};
        RI(RC(@"AnimatorStatesController"),NULL,@"SetAnimatorParameter",@[@"AnimatorStatesData",@"System.String",@"System.Boolean"],args,&error);
    } else if([command isEqualToString:@"resetAnimator"]) {
        void *args[]={states};RI(RC(@"AnimatorStatesController"),NULL,@"ResetAllAnimatorParameters",@[@"AnimatorStatesData"],args,&error);
    } else if([command isEqualToString:@"state"]) {
        void *animator=RF(RAnimation(),"animator");NSString *path=values[0];NSString *layerName=[[path componentsSeparatedByString:@"."] firstObject];void *layerString=r_string_new(layerName.UTF8String);void *la[]={layerString};int layer=RInt(RCall(animator,@"GetLayerIndex",@[@"System.String"],la));
        void *str=r_string_new(path.UTF8String);void *sa[]={str};int hash=RInt(RI(r_object_get_class(animator),NULL,@"StringToHash",@[@"System.String"],sa,&error));
        void *ha[]={&layer,&hash};if(layer<0||!RBool(RCall(animator,@"HasState",@[@"System.Int32",@"System.Int32"],ha)))return @"Состояние отсутствует в активном Animator";
        float time=0;void *args[]={str,&layer,&time};RI(r_object_get_class(animator),animator,@"Play",@[@"System.String",@"System.Int32",@"System.Single"],args,&error);
    } else if([command isEqualToString:@"danceSpeed"]) {
        float speed=[values[0] floatValue];void *args[]={states,&speed};RI(RC(@"AnimatorStatesController"),NULL,@"SetDanceSpeed",@[@"AnimatorStatesData",@"System.Single"],args,&error);
    } else if([command isEqualToString:@"viewYaw"]) {
        void *transform=RCall(RCharacter(),@"get_transform",@[],NULL);static void *lastTransform;static float initial[3];
        if(lastTransform!=transform){void *boxed=RCall(transform,@"get_localEulerAngles",@[],NULL);if(!boxed)return @"Поворот недоступен";memcpy(initial,r_object_unbox(boxed),sizeof(initial));lastTransform=transform;}
        float euler[]={initial[0],initial[1]+[values[0] floatValue],initial[2]};void *args[]={euler};RI(r_object_get_class(transform),transform,@"set_localEulerAngles",@[@"UnityEngine.Vector3"],args,&error);
    } else if([command isEqualToString:@"distance"]) {
        float distance=[values[0] floatValue];void *args[]={&distance};RI(RC(@"WardrobeNativeApiDelegateImpl"),NULL,@"SetCameraDistance",@[@"System.Single"],args,&error);
    } else if([command isEqualToString:@"settings"]) {
        int b=[values[0] intValue],f=[values[1] intValue],bs=[values[2] intValue],fs=[values[3] intValue];void *args[]={&b,&f,&bs,&fs};RI(RC(@"NativeApiDelegateImpl"),NULL,@"UpdateAnimationGenerationSettings",@[@"System.Int32",@"System.Int32",@"System.Int32",@"System.Int32"],args,&error);
    } else if([command isEqualToString:@"rbf"]) {
        bool value=[values[0] boolValue];void *args[]={&value};RI(RC(@"NativeApiDelegateImpl"),NULL,@"SetRBFActive",@[@"System.Boolean"],args,&error);
    } else if([command isEqualToString:@"backgroundTiming"]) {
        int value=[values[0] intValue];void *args[]={&value};RI(RC(@"BackgroundsNativeApiDelegateImpl"),NULL,@"SetBackgroundTimingMode",@[@"System.Int32"],args,&error);
    } else if([@[@"InterruptInference",@"StartReview",@"StopReview",@"PlayReview",@"PauseReview"] containsObject:command]) {
        RI(RC(@"NativeApiDelegateImpl"),NULL,command,@[],NULL,&error);
    } else if([command isEqualToString:@"SetReviewProgress"]) {
        float progress=[values[0] floatValue];void *args[]={&progress};RI(RC(@"NativeApiDelegateImpl"),NULL,command,@[@"System.Single"],args,&error);
    } else return @"Неизвестная команда";
    fprintf(stderr,"[DevRuntime] %s %s -> %s\n",command.UTF8String,values.description.UTF8String,error?error.UTF8String:"sent");
    return error;
}
int DevRuntimeSampleRate(void) {if(!RInit())return 0;return RInt(RS(@"CharacterData","EXPECTED_AUDIO_SAMPLE_RATE"));}
NSString *DevRuntimeFace(NSDictionary *weights) {
    if(!RInit()||!RScene()||!RFaceChannels().count)return @"У персонажа нет подключённых лицевых каналов";
    NSString *error=nil;void *ch=RCharacter();
    if(!weights) {
        void *job=RF(RF(RAnimation(),"aiJobData"),"blendShapesJobData");
        RI(r_object_get_class(job),job,@"Interrupt",@[],NULL,&error);
        fprintf(stderr,"[DevRuntime] face reset\n");return error;
    }
    int width=RInt(RS(@"CharacterAnimationData","BLEND_SHAPES_COUNT"));
    int fps=RInt(RS(@"CharacterAnimationData","FPS"));if(width<=0||width>256||fps<=0||fps>120)return @"Неизвестный формат мимики";
    int frames=fps*5;NSMutableData *data=[NSMutableData dataWithLength:frames*width*sizeof(float)];float *samples=data.mutableBytes;
    for(NSDictionary *channel in RFaceChannels()) {
        int index=[channel[@"index"] intValue];if(index>=width)continue;float weight=MAX(0,MIN(1,[weights[channel[@"name"]] floatValue]));
        for(int frame=0;frame<frames;frame++)samples[frame*width+index]=weight;
    }
    const void *bytes=data.bytes;void *a[]={&bytes,&frames};
    void *blend=RI(RC(@"NativeApiDelegateImpl"),NULL,@"CreateAIBlendShapesData",@[@"System.IntPtr",@"System.Int32"],a,&error);
    void *emptyAudio=RS(@"AIAudioData","EMPTY");
    if(error||!blend||!emptyAudio)return error?:@"Не удалось создать буфер мимики";
    int state=RInt(RS(@"CharacterAnimationBufferState","COMMAND_ANIMATION_ULTIMATE"));
    void *args[]={ch,r_object_unbox(blend),r_object_unbox(emptyAudio),&state};
    RI(RC(@"AICharacterController"),NULL,@"StartNewBlendShapesData",@[@"CharacterData",@"AIBlendShapesData",@"AIAudioData",@"CharacterAnimationData.CharacterAnimationBufferState"],args,&error);
    // The original Interrupt copies input into its NativeLists before returning.
    fprintf(stderr,"[DevRuntime] face frames=%d channels=%d weights=%s -> %s\n",frames,width,weights.description.UTF8String,error?error.UTF8String:"sent");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,700*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(RCharacter()!=ch)return;void *face=RF(RAnimation(),"face");NSMutableDictionary *actual=[NSMutableDictionary new];
        for(NSDictionary *channel in RFaceChannels()){int index=[channel[@"meshIndex"] intValue];void *v[]={&index};actual[channel[@"name"]]=@(RFloat(RCall(face,@"GetBlendShapeWeight",@[@"System.Int32"],v)));}
        NSDictionary *report=@{@"requested":weights,@"actualMeshWeights":actual};
        [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/AnimatesDev/runtime-face.json"] atomically:YES];
    });
    return error;
}
NSString *DevRuntimeSpeech(NSData *audio) {
    if(!RInit()||!RScene())return @"Сцена не загружена";
    NSString *id=NSUUID.UUID.UUIDString;const char *p=id.UTF8String;const void *bytes=audio.bytes;int count=(int)(audio.length/sizeof(float));void *args[]={&p,&bytes,&count};NSString *error=nil;
    RI(RC(@"NativeApiDelegateImpl"),NULL,@"AppendInferenceSpeech",@[@"System.IntPtr",@"System.IntPtr",@"System.Int32"],args,&error);
    if(!error){void *done[]={&p};RI(RC(@"NativeApiDelegateImpl"),NULL,@"CompleteInferenceSpeech",@[@"System.IntPtr"],done,&error);}
    fprintf(stderr,"[DevRuntime] speech samples=%d -> %s\n",count,error?error.UTF8String:"sent");return error;
}
