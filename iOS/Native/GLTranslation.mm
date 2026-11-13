#import "GLTranslation.h"
#include <ctranslate2/translator.h>
#include <sentencepiece_processor.h>
#include <atomic>
#include <memory>

@implementation GLTranslation {
    std::unique_ptr<ctranslate2::Translator> _translator;
    sentencepiece::SentencePieceProcessor _tokenizer;
    std::atomic<bool> _cancelled;
}
- (instancetype)initWithModelPath:(NSString *)path error:(NSError **)error {
    self=[super init];if(!self)return nil;
    try {
        _cancelled.store(false);
        auto status=_tokenizer.Load(std::string(path.UTF8String)+"/sentencepiece.model");
        if(!status.ok())throw std::runtime_error("Tokenizer initialization failed");
        ctranslate2::ReplicaPoolConfig config;config.num_threads_per_replica=2;
        // int8 on ARM64 uses Ruy. The simulator uses float32/Accelerate.
#if defined(__aarch64__)
        auto type=ctranslate2::ComputeType::INT8;
#else
        auto type=ctranslate2::ComputeType::FLOAT32;
#endif
        _translator=std::make_unique<ctranslate2::Translator>(std::string(path.UTF8String)+"/model",ctranslate2::Device::CPU,type,std::vector<int>{0},false,config);
        return self;
    } catch(const std::exception &) {
        if(error)*error=[NSError errorWithDomain:@"GameLingo.Translation" code:1 userInfo:@{NSLocalizedDescriptionKey:@"تعذر تحميل نموذج الترجمة المحلي"}];
        return nil;
    }
}
- (void)cancel { _cancelled.store(true); }
- (void)resume { _cancelled.store(false); }
- (NSString *)translate:(NSString *)text error:(NSError **)error {
    try {
        std::vector<std::string> pieces;
        if(!_tokenizer.Encode(text.UTF8String,&pieces).ok())throw std::runtime_error("Tokenization failed");
        ctranslate2::TranslationOptions options;options.beam_size=1;
        options.max_decoding_length=std::min<size_t>(256,std::max<size_t>(24,2*pieces.size()+12));
        options.callback=[self](ctranslate2::GenerationStepResult) { return self->_cancelled.load(); };
        if(_cancelled.load())throw std::runtime_error("Cancelled");
        auto result=_translator->translate_batch({pieces},options);
        if(_cancelled.load() || result.empty() || result[0].hypotheses.empty())throw std::runtime_error("No result");
        std::string output;
        if(!_tokenizer.Decode(result[0].hypotheses[0],&output).ok() || output.empty())throw std::runtime_error("Empty translation");
        return [[NSString alloc] initWithBytes:output.data() length:output.size() encoding:NSUTF8StringEncoding];
    } catch(const std::exception &) {
        if(error)*error=[NSError errorWithDomain:@"GameLingo.Translation" code:2 userInfo:@{NSLocalizedDescriptionKey:@"تعذرت الترجمة أو أُلغيت نتيجة قديمة"}];
        return nil;
    }
}
@end
