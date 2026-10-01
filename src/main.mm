#import <Foundation/Foundation.h>
#include <vector>
#include <string>
extern int PlayerMain(int argc, const char **argv);
int main(int argc, const char **argv) {
    @autoreleasepool {
        NSString *logs = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/AnimatesDev"];
        [NSFileManager.defaultManager createDirectoryAtPath:logs withIntermediateDirectories:YES attributes:nil error:nil];
        std::vector<std::string> args = {argv[0], "-screen-fullscreen", "0", "-screen-width", "960", "-screen-height", "900", "-logFile", [[logs stringByAppendingPathComponent:@"Unity.log"] UTF8String]};
        for (int i=1;i<argc;i++) args.emplace_back(argv[i]);
        std::vector<const char *> ptrs; for (auto &arg:args) ptrs.push_back(arg.c_str());
        return PlayerMain((int)ptrs.size(), ptrs.data());
    }
}
