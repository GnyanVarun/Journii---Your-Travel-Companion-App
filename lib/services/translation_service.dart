import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

class TranslationService {
  TranslationService._();

  static final LanguageIdentifier _languageIdentifier =
  LanguageIdentifier(confidenceThreshold: 0.5);

  static final OnDeviceTranslatorModelManager _modelManager =
  OnDeviceTranslatorModelManager();

  /// Translates [text] to English when the source language is not English.
  ///
  /// Returns the original text when:
  /// - the text is empty
  /// - the language cannot be confidently identified
  /// - the text is already English
  /// - the language is not supported by ML Kit translation
  /// - translation fails
  static Future<String> translateToEnglish(String text) async {
    final originalText = text.trim();

    if (originalText.isEmpty) {
      return text;
    }

    try {
      final languageCode =
      await _languageIdentifier.identifyLanguage(originalText);

      if (languageCode == 'und' || languageCode.isEmpty) {
        return text;
      }

      if (languageCode.toLowerCase() == 'en') {
        return text;
      }

      final sourceLanguage =
      BCP47Code.fromRawValue(languageCode);

      if (sourceLanguage == null) {
        return text;
      }

      final targetLanguage = TranslateLanguage.english;

      if (sourceLanguage == targetLanguage) {
        return text;
      }

      await _modelManager.downloadModel(
        sourceLanguage.bcpCode,
        isWifiRequired: false,
      );

      await _modelManager.downloadModel(
        targetLanguage.bcpCode,
        isWifiRequired: false,
      );

      final translator = OnDeviceTranslator(
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      );

      try {
        final translatedText =
        await translator.translateText(originalText);

        return translatedText.trim().isNotEmpty
            ? translatedText
            : text;
      } finally {
        await translator.close();
      }
    } catch (e) {
      print('Translation error: $e');
      return text;
    }
  }

  static Future<String?> detectLanguage(String text) async {
    final value = text.trim();

    if (value.isEmpty) {
      return null;
    }

    try {
      final languageCode =
      await _languageIdentifier.identifyLanguage(value);

      if (languageCode == 'und' || languageCode.isEmpty) {
        return null;
      }

      return languageCode;
    } catch (e) {
      print('Language identification error: $e');
      return null;
    }
  }

  static Future<void> dispose() async {
    await _languageIdentifier.close();
  }
}