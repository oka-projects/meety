#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Executa um bloco capturando qualquer `NSException` lançada.
///
/// O Swift não consegue capturar exceções Objective-C (um `@throw` vira `abort()`).
/// Algumas APIs do AVFoundation, em especial o encerramento do `AVAssetWriter`
/// (`markAsFinished` e `finishWriting`), lançam `NSException` em estados de borda e
/// derrubariam o app inteiro. Este invólucro transforma isso num `NSError` recuperável.
///
/// Devolve `nil` se o bloco rodou sem exceção; senão um `NSError` cujo `userInfo` traz o
/// nome e a razão da exceção original.
@interface MTExceptionCatcher : NSObject
+ (NSError *_Nullable)catching:(NS_NOESCAPE void (^)(void))block
    NS_SWIFT_NAME(catching(_:));
@end

NS_ASSUME_NONNULL_END
