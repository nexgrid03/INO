import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/widgets.dart';

/// Lightweight, dependency-free localization for INO.
///
/// Supported languages: English (`en`), Hindi (`hi`), Telugu (`te`) and Tamil
/// (`ta`). Strings are looked up by key with an English fallback, so a missing
/// translation degrades gracefully rather than showing a blank or crashing.
///
/// Usage:
/// ```dart
/// final l10n = AppLocalizations.of(context);
/// Text(l10n.t('save'));
/// ```
///
/// The active locale is driven by [MaterialApp.locale] (see `main.dart`), which
/// in turn follows the persisted `AppSettings.language`. Changing the language
/// rebuilds every `Localizations` dependant instantly — no restart.
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  /// The locales the app ships translations for.
  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('hi'),
    Locale('te'),
    Locale('ta'),
  ];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// English fallback used when no [AppLocalizations] is in the tree (e.g. a
  /// widget test that doesn't register the delegate) — never returns null.
  static const AppLocalizations _fallback = AppLocalizations(Locale('en'));

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ?? _fallback;

  /// Translates [key] into the active language, falling back to English and
  /// finally to the key itself (so a typo is visible rather than blank).
  String t(String key) {
    final lang = _strings[locale.languageCode] ?? _strings['en']!;
    return lang[key] ?? _strings['en']![key] ?? key;
  }

  // Convenience getters for the highest-traffic strings.
  String get home => t('home');
  String get wallet => t('wallet');
  String get scan => t('scan');
  String get reminders => t('reminders');
  String get profile => t('profile');

  String get save => t('save');
  String get cancel => t('cancel');
  String get create => t('create');
  String get upload => t('upload');
  String get delete => t('delete');
  String get retake => t('retake');

  String get crop => t('crop');
  String get rotate => t('rotate');
  String get enhance => t('enhance');

  String get language => t('language');
  String get notifications => t('notifications');
  String get darkMode => t('darkMode');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      const {'en', 'hi', 'te', 'ta'}.contains(locale.languageCode);

  // Resolve synchronously (like Flutter's own delegates) so switching language
  // never flashes an empty frame and the widget tree builds in the same frame.
  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

/// The translation table: `languageCode → (key → value)`. English is the source
/// of truth; the other three mirror its keys. Keep keys in sync across all four.
const Map<String, Map<String, String>> _strings = {
  'en': {
    // Navigation
    'home': 'Home',
    'wallet': 'Wallet',
    'scan': 'Scan',
    'reminders': 'Reminders',
    'profile': 'Profile',
    // Buttons / common
    'upload': 'Upload',
    'create': 'Create',
    'save': 'Save',
    'cancel': 'Cancel',
    'continue': 'Continue',
    'delete': 'Delete',
    'retake': 'Retake',
    'add': 'Add',
    'search': 'Search',
    'edit': 'Edit',
    'share': 'Share',
    'open': 'Open',
    'done': 'Done',
    'ok': 'OK',
    // Settings
    'language': 'Language',
    'notifications': 'Notifications',
    'darkMode': 'Dark Mode',
    'security': 'Security',
    'preferences': 'Preferences',
    'support': 'Support',
    'legal': 'Legal',
    'account': 'Account',
    // Document module
    'scanDocument': 'Scan Document',
    'uploadPdf': 'Upload PDF',
    'uploadImage': 'Upload Image',
    'importImage': 'Import Image',
    'reviewCapture': 'Review Capture',
    'crop': 'Crop',
    'rotate': 'Rotate',
    'enhance': 'Enhance',
    'addDocument': 'Add Document',
    'saveDocument': 'Save Document',
    'documentName': 'Document Name',
    'category': 'Category',
    'expiryDate': 'Expiry Date',
    'notes': 'Notes',
    'tags': 'Tags',
    'selectCategory': 'Select Category',
    'selectWallet': 'Select Wallet',
    'createCategory': 'Create Category',
    'newCategory': 'New Category',
    'chooseCategory': 'Choose a category',
    'chooseWallet': 'Choose a wallet',
    // Empty states
    'noDocumentsYet': 'No Documents Yet',
    'noActivity': 'No Activity',
    'noReminders': 'No Reminders',
    // Success / error
    'documentSaved': 'Document Saved',
    'uploadSuccessful': 'Upload Successful',
    'deleteSuccessful': 'Delete Successful',
    'invalidFile': 'Invalid File',
  },
  'hi': {
    'home': 'होम',
    'wallet': 'वॉलेट',
    'scan': 'स्कैन',
    'reminders': 'रिमाइंडर',
    'profile': 'प्रोफ़ाइल',
    'upload': 'अपलोड',
    'create': 'बनाएँ',
    'save': 'सहेजें',
    'cancel': 'रद्द करें',
    'continue': 'जारी रखें',
    'delete': 'हटाएँ',
    'retake': 'फिर से लें',
    'add': 'जोड़ें',
    'search': 'खोजें',
    'edit': 'संपादित करें',
    'share': 'साझा करें',
    'open': 'खोलें',
    'done': 'पूर्ण',
    'ok': 'ठीक है',
    'language': 'भाषा',
    'notifications': 'सूचनाएँ',
    'darkMode': 'डार्क मोड',
    'security': 'सुरक्षा',
    'preferences': 'प्राथमिकताएँ',
    'support': 'सहायता',
    'legal': 'कानूनी',
    'account': 'खाता',
    'scanDocument': 'दस्तावेज़ स्कैन करें',
    'uploadPdf': 'PDF अपलोड करें',
    'uploadImage': 'छवि अपलोड करें',
    'importImage': 'छवि आयात करें',
    'reviewCapture': 'कैप्चर की समीक्षा करें',
    'crop': 'क्रॉप करें',
    'rotate': 'घुमाएँ',
    'enhance': 'बेहतर बनाएँ',
    'addDocument': 'दस्तावेज़ जोड़ें',
    'saveDocument': 'दस्तावेज़ सहेजें',
    'documentName': 'दस्तावेज़ का नाम',
    'category': 'श्रेणी',
    'expiryDate': 'समाप्ति तिथि',
    'notes': 'नोट्स',
    'tags': 'टैग',
    'selectCategory': 'श्रेणी चुनें',
    'selectWallet': 'वॉलेट चुनें',
    'createCategory': 'श्रेणी बनाएँ',
    'newCategory': 'नई श्रेणी',
    'chooseCategory': 'श्रेणी चुनें',
    'chooseWallet': 'वॉलेट चुनें',
    'noDocumentsYet': 'अभी तक कोई दस्तावेज़ नहीं',
    'noActivity': 'कोई गतिविधि नहीं',
    'noReminders': 'कोई रिमाइंडर नहीं',
    'documentSaved': 'दस्तावेज़ सहेजा गया',
    'uploadSuccessful': 'अपलोड सफल',
    'deleteSuccessful': 'हटाना सफल',
    'invalidFile': 'अमान्य फ़ाइल',
  },
  'te': {
    'home': 'హోమ్',
    'wallet': 'వాలెట్',
    'scan': 'స్కాన్',
    'reminders': 'రిమైండర్‌లు',
    'profile': 'ప్రొఫైల్',
    'upload': 'అప్‌లోడ్',
    'create': 'సృష్టించు',
    'save': 'సేవ్ చేయి',
    'cancel': 'రద్దు చేయి',
    'continue': 'కొనసాగించు',
    'delete': 'తొలగించు',
    'retake': 'మళ్లీ తీయి',
    'add': 'జోడించు',
    'search': 'వెతుకు',
    'edit': 'సవరించు',
    'share': 'షేర్ చేయి',
    'open': 'తెరువు',
    'done': 'పూర్తయింది',
    'ok': 'సరే',
    'language': 'భాష',
    'notifications': 'నోటిఫికేషన్‌లు',
    'darkMode': 'డార్క్ మోడ్',
    'security': 'భద్రత',
    'preferences': 'ప్రాధాన్యతలు',
    'support': 'మద్దతు',
    'legal': 'చట్టపరమైన',
    'account': 'ఖాతా',
    'scanDocument': 'డాక్యుమెంట్ స్కాన్ చేయి',
    'uploadPdf': 'PDF అప్‌లోడ్ చేయి',
    'uploadImage': 'చిత్రం అప్‌లోడ్ చేయి',
    'importImage': 'చిత్రం దిగుమతి చేయి',
    'reviewCapture': 'క్యాప్చర్‌ను సమీక్షించు',
    'crop': 'క్రాప్ చేయి',
    'rotate': 'తిప్పు',
    'enhance': 'మెరుగుపరచు',
    'addDocument': 'డాక్యుమెంట్ జోడించు',
    'saveDocument': 'డాక్యుమెంట్ సేవ్ చేయి',
    'documentName': 'డాక్యుమెంట్ పేరు',
    'category': 'వర్గం',
    'expiryDate': 'గడువు తేదీ',
    'notes': 'గమనికలు',
    'tags': 'ట్యాగ్‌లు',
    'selectCategory': 'వర్గాన్ని ఎంచుకోండి',
    'selectWallet': 'వాలెట్‌ను ఎంచుకోండి',
    'createCategory': 'వర్గాన్ని సృష్టించు',
    'newCategory': 'కొత్త వర్గం',
    'chooseCategory': 'వర్గాన్ని ఎంచుకోండి',
    'chooseWallet': 'వాలెట్‌ను ఎంచుకోండి',
    'noDocumentsYet': 'ఇంకా డాక్యుమెంట్‌లు లేవు',
    'noActivity': 'కార్యకలాపం లేదు',
    'noReminders': 'రిమైండర్‌లు లేవు',
    'documentSaved': 'డాక్యుమెంట్ సేవ్ అయింది',
    'uploadSuccessful': 'అప్‌లోడ్ విజయవంతమైంది',
    'deleteSuccessful': 'తొలగింపు విజయవంతమైంది',
    'invalidFile': 'చెల్లని ఫైల్',
  },
  'ta': {
    'home': 'முகப்பு',
    'wallet': 'வாலெட்',
    'scan': 'ஸ்கேன்',
    'reminders': 'நினைவூட்டல்கள்',
    'profile': 'சுயவிவரம்',
    'upload': 'பதிவேற்று',
    'create': 'உருவாக்கு',
    'save': 'சேமி',
    'cancel': 'ரத்து செய்',
    'continue': 'தொடர்',
    'delete': 'நீக்கு',
    'retake': 'மீண்டும் எடு',
    'add': 'சேர்',
    'search': 'தேடு',
    'edit': 'திருத்து',
    'share': 'பகிர்',
    'open': 'திற',
    'done': 'முடிந்தது',
    'ok': 'சரி',
    'language': 'மொழி',
    'notifications': 'அறிவிப்புகள்',
    'darkMode': 'இருண்ட பயன்முறை',
    'security': 'பாதுகாப்பு',
    'preferences': 'விருப்பங்கள்',
    'support': 'ஆதரவு',
    'legal': 'சட்டப்பூர்வ',
    'account': 'கணக்கு',
    'scanDocument': 'ஆவணத்தை ஸ்கேன் செய்',
    'uploadPdf': 'PDF பதிவேற்று',
    'uploadImage': 'படத்தைப் பதிவேற்று',
    'importImage': 'படத்தை இறக்கு',
    'reviewCapture': 'பிடிப்பை மதிப்பாய்வு செய்',
    'crop': 'வெட்டு',
    'rotate': 'சுழற்று',
    'enhance': 'மேம்படுத்து',
    'addDocument': 'ஆவணத்தைச் சேர்',
    'saveDocument': 'ஆவணத்தைச் சேமி',
    'documentName': 'ஆவணத்தின் பெயர்',
    'category': 'வகை',
    'expiryDate': 'காலாவதி தேதி',
    'notes': 'குறிப்புகள்',
    'tags': 'குறிச்சொற்கள்',
    'selectCategory': 'வகையைத் தேர்ந்தெடு',
    'selectWallet': 'வாலெட்டைத் தேர்ந்தெடு',
    'createCategory': 'வகையை உருவாக்கு',
    'newCategory': 'புதிய வகை',
    'chooseCategory': 'வகையைத் தேர்ந்தெடுக்கவும்',
    'chooseWallet': 'வாலெட்டைத் தேர்ந்தெடுக்கவும்',
    'noDocumentsYet': 'இன்னும் ஆவணங்கள் இல்லை',
    'noActivity': 'செயல்பாடு இல்லை',
    'noReminders': 'நினைவூட்டல்கள் இல்லை',
    'documentSaved': 'ஆவணம் சேமிக்கப்பட்டது',
    'uploadSuccessful': 'பதிவேற்றம் வெற்றி',
    'deleteSuccessful': 'நீக்கம் வெற்றி',
    'invalidFile': 'தவறான கோப்பு',
  },
};
