#import <Avocado/Avocado-Swift.h>
#import "AVCPluginMethod.h"

@implementation AVCPluginMethodArgument

- (instancetype)initWithName:(NSString *)name nullability:(AVCPluginMethodArgumentNullability)nullability type:(NSString *)type {
  self.name = name;
  self.type = type;
  self.nullability = nullability;
  return self;
}

@end

@implementation AVCPluginMethod

-(instancetype)initWithNameAndTypes:(NSString *)name types:(NSString *)types returnType:(AVCPluginReturnType *)returnType {
  self.name = name;
  self.types = types;
  self.returnType = returnType;
  self.args = [self makeArgs];
  self.selector = [self makeSelector];
  
  return self;
}

-(NSArray<AVCPluginMethodArgument *> *)makeArgs {
  NSMutableArray<AVCPluginMethodArgument *> *parts = [[NSMutableArray alloc] init];
  NSArray *typeParts = [self.types componentsSeparatedByString:@","];
  for(NSString *t in typeParts) {
    NSString *paramPart = [t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSArray *paramParts = [paramPart componentsSeparatedByString:@":"];
    NSString *paramName = [[NSString alloc] initWithString:[paramParts objectAtIndex:0]];
    NSString *typeName = [[NSString alloc] initWithString:[paramParts objectAtIndex:1]];
    NSString *flag = [paramName substringFromIndex:MAX([paramName length] - 1, 0)];
    AVCPluginMethodArgumentNullability nullability = AVCPluginMethodArgumentNotNullable;
    if([flag isEqualToString:@"?"]) {
      nullability = AVCPluginMethodArgumentNullable;
      paramName = [paramName substringWithRange:NSMakeRange(0, [paramName length] - 1)];
    }
    AVCPluginMethodArgument *arg = [[AVCPluginMethodArgument alloc] initWithName:paramName nullability:nullability type:typeName];
    [parts addObject:arg];
  }
  return parts;
}

/**
 * Make an objective-c selector for the given plugin method.
 */
-(SEL)makeSelector {
  NSMutableString *nameSelector = [[NSMutableString alloc] initWithString:self.name];
  [nameSelector appendString:@":"];
  NSMutableArray *selectorParts = [[NSMutableArray alloc] initWithObjects:nameSelector, nil];
  NSArray *typeParts = [self.types componentsSeparatedByString:@","];
  
  // We skip the first param because Objective-C selectors don't use the first argument
  // as part of the selector. Example: method setName with arg "name:string" becomes just setName:
  if([typeParts count] > 1) {
    NSArray *typePartsMinusFirstArg = [typeParts subarrayWithRange:NSMakeRange(1, [typeParts count]-1)];
    for(NSString *t in typePartsMinusFirstArg) {
      NSString *paramPart = [t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      NSArray *paramParts = [paramPart componentsSeparatedByString:@":"];
      NSMutableString *paramName = [[NSMutableString alloc] initWithString:[paramParts objectAtIndex:0]];
      [paramName appendString:@":"];
      [selectorParts addObject:paramName];
    }
  }
  // Add our required success/error callback handlers
  [selectorParts addObject:@"success:error:"];
  NSString *selectorString = [selectorParts componentsJoinedByString:@""];
  return NSSelectorFromString(selectorString);
}

-(SEL)getSelector {
  return self.selector;
}

// See https://stackoverflow.com/a/3224774/32140 for NSInvocation background
-(void)invoke:(AVCPluginCall *)pluginCall onPlugin:(AVCPlugin *)plugin {
  NSMutableArray *args = [[NSMutableArray alloc] initWithCapacity:[pluginCall.options count]];
  NSDictionary *options = pluginCall.options;
  
  NSMethodSignature * mySignature = [plugin methodSignatureForSelector:self.selector];

  NSInvocation * myInvocation = [NSInvocation
                                 invocationWithMethodSignature:mySignature];
  [myInvocation setTarget:plugin];
  [myInvocation setSelector:self.selector];
  NSUInteger numArgs = [self.args count];
  for(int i = 0; i < numArgs; i++) {
    AVCPluginMethodArgument *arg = [self.args objectAtIndex:i];
    id callArg = [options objectForKey:arg];
    NSLog(@"Found callArg and arg %@ %@", callArg, arg);
    [myInvocation setArgument:&arg atIndex:i+2]; // We're at an offset of 2 for the invocation args
  }
  
  const AVCPluginCallSuccessHandler *successHandler = [pluginCall getSuccessHandler];
  const AVCPluginCallErrorHandler *errorHandler = [pluginCall getErrorHandler];
  
  [myInvocation setArgument:&successHandler atIndex:numArgs];
  [myInvocation setArgument:&errorHandler atIndex:numArgs+1];
  
  // TODO: Look into manual retain per online discussion
  // http://www.cocoabuilder.com/archive/cocoa/241994-surprise-nsinvocation-retainarguments-also-autoreleases-them.html
  // Possible adding to autorelease pool is not desirable given our lifecycle
  [myInvocation retainArguments];
  
  CFTimeInterval start = CACurrentMediaTime();
  [myInvocation invoke];
  CFTimeInterval duration = CACurrentMediaTime() - start;
  NSLog(@"Method invocation took %@", duration);
}
@end

