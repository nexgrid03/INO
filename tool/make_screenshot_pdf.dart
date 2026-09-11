// Builds INO_PlayStore_Screenshots.pdf from the PNGs in test/screenshots/.
//
// Regenerate the PNGs first:
//   flutter test test/playstore_screenshots.dart --update-goldens
// then:
//   dart run tool/make_screenshot_pdf.dart
library;

import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _ink = PdfColor.fromInt(0xFF0F2432);
const _muted = PdfColor.fromInt(0xFF5B7180);
const _brand = PdfColor.fromInt(0xFF0EA5E9);
const _teal = PdfColor.fromInt(0xFF00A86B);
const _rule = PdfColor.fromInt(0xFFDCE7EE);
const _panel = PdfColor.fromInt(0xFFF3F8FB);

class _Shot {
  const _Shot(this.file, this.slot, this.screen, this.caption, this.bullets);

  /// File name inside test/screenshots/.
  final String file;

  /// Suggested position in the Play Store carousel.
  final String slot;

  /// Which screen of the app this is.
  final String screen;

  /// The short line to set beside the screenshot in the store listing.
  final String caption;

  /// What a reviewer / user is looking at.
  final List<String> bullets;
}

const _shots = <_Shot>[
  _Shot(
    '01_home.png',
    'Screenshot 1',
    'Home dashboard',
    'Everything you own, in one place',
    [
      'The landing screen after sign-in: vault status, quick actions and the '
          'wallet strip.',
      'Quick Actions put Scan, Documents, Reminder and Voice one tap from the '
          'home screen.',
      'Put this first - it is the screen Play shows in search results.',
    ],
  ),
  _Shot(
    '02_wallets.png',
    'Screenshot 2',
    'My Wallets hub',
    'Eight wallets, one secure vault',
    [
      'Identity, Document, Property, Insurance, Health, Investment, Banking '
          'and Password wallets.',
      'Each tile carries its own live record count, so the hub doubles as a '
          'summary.',
      'This is the clearest single image of what the app actually does.',
    ],
  ),
  _Shot(
    '03_identity_wallet.png',
    'Screenshot 3',
    'Inside a wallet (Identity)',
    'Scan, upload or create - your IDs stay encrypted',
    [
      'What opening a wallet looks like: the document list plus Scan, Upload '
          'and Create actions.',
      'Shows the in-wallet QR action and the bottom navigation dock.',
      'Pairs naturally with Screenshot 2 - hub, then detail.',
    ],
  ),
  _Shot(
    '04_reminders.png',
    'Screenshot 4',
    'Reminders',
    'Never miss a renewal again',
    [
      'Reminders for renewals, EMIs, policy expiries and document deadlines.',
      'Push notifications fire to the minute, not in five-minute blocks.',
      'Good fourth slot: it sells retention rather than storage.',
    ],
  ),
  _Shot(
    '05_finance_tools.png',
    'Screenshot 5',
    'Property & Finance Tools',
    'Indian land units, EMI, SIP, gold and tax - built in',
    [
      'Area converter, property valuation, EMI, SIP, gold, currency and tax '
          'calculators.',
      'The clearest differentiator against a plain document-storage app.',
      'Strong for the Indian market: the area converter handles local land '
          'units.',
    ],
  ),
  _Shot(
    '06_onboarding_qr.png',
    'Screenshot 6',
    'Onboarding - Share Instantly & Safely',
    'Share documents by QR, protected by biometrics',
    [
      'The third onboarding slide, covering secure QR sharing.',
      'Already carries its own headline and body copy - it reads well with no '
          'added text.',
      'Works as the closing frame of the carousel.',
    ],
  ),
];

Future<void> main() async {
  final root = Directory.current.path;
  final shotDir = Directory('$root/test/screenshots');
  if (!shotDir.existsSync()) {
    stderr.writeln(
      'test/screenshots/ is missing. Run:\n'
      '  flutter test test/playstore_screenshots.dart --update-goldens',
    );
    exit(1);
  }

  final doc = pw.Document(
    title: 'INO - Google Play Store screenshots',
    author: 'INO',
  );

  final images = <String, pw.MemoryImage>{};
  for (final shot in _shots) {
    final file = File('${shotDir.path}/${shot.file}');
    if (!file.existsSync()) {
      stderr.writeln('Missing ${shot.file} - skipping.');
      continue;
    }
    images[shot.file] = pw.MemoryImage(file.readAsBytesSync());
  }

  doc.addPage(_coverPage());
  for (final shot in _shots) {
    final image = images[shot.file];
    if (image == null) continue;
    doc.addPage(_shotPage(shot, image));
  }
  doc.addPage(_howToPage());
  doc.addPage(_checklistPage());

  final out = File('$root/INO_PlayStore_Screenshots.pdf');
  await out.writeAsBytes(await doc.save());
  stdout.writeln('Wrote ${out.path}');
}

// ---------------------------------------------------------------------------
// Shared chrome
// ---------------------------------------------------------------------------

pw.PageTheme _theme() => pw.PageTheme(
  pageFormat: PdfPageFormat.a4,
  margin: const pw.EdgeInsets.fromLTRB(42, 44, 42, 40),
  buildBackground: (context) => pw.FullPage(
    ignoreMargins: true,
    child: pw.Container(color: PdfColors.white),
  ),
);

pw.Widget _h1(String text) => pw.Text(
  text,
  style: pw.TextStyle(
    fontSize: 22,
    fontWeight: pw.FontWeight.bold,
    color: _ink,
  ),
);

pw.Widget _h2(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
  child: pw.Text(
    text,
    style: pw.TextStyle(
      fontSize: 13,
      fontWeight: pw.FontWeight.bold,
      color: _ink,
    ),
  ),
);

pw.Widget _body(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 5),
  child: pw.Text(
    text,
    style: const pw.TextStyle(fontSize: 10, color: _muted, lineSpacing: 2.2),
  ),
);

pw.Widget _bullet(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 5),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(
        width: 4,
        height: 4,
        margin: const pw.EdgeInsets.only(top: 4.5, right: 7),
        decoration: const pw.BoxDecoration(
          color: _brand,
          shape: pw.BoxShape.circle,
        ),
      ),
      pw.Expanded(
        child: pw.Text(
          text,
          style: const pw.TextStyle(
            fontSize: 10,
            color: _muted,
            lineSpacing: 2.2,
          ),
        ),
      ),
    ],
  ),
);

pw.Widget _numbered(int n, String title, String detail) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 9),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(
        width: 17,
        height: 17,
        margin: const pw.EdgeInsets.only(right: 9),
        alignment: pw.Alignment.center,
        decoration: const pw.BoxDecoration(
          color: _brand,
          shape: pw.BoxShape.circle,
        ),
        child: pw.Text(
          '$n',
          style: pw.TextStyle(
            fontSize: 9,
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
                color: _ink,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              detail,
              style: const pw.TextStyle(
                fontSize: 9.5,
                color: _muted,
                lineSpacing: 2.2,
              ),
            ),
          ],
        ),
      ),
    ],
  ),
);

pw.Widget _note(String title, String text, {PdfColor accent = _teal}) =>
    pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        color: _panel,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border(left: pw.BorderSide(color: accent, width: 2.5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            text,
            style: const pw.TextStyle(
              fontSize: 9.5,
              color: _muted,
              lineSpacing: 2.2,
            ),
          ),
        ],
      ),
    );

// ---------------------------------------------------------------------------
// Pages
// ---------------------------------------------------------------------------

pw.Page _coverPage() => pw.Page(
  pageTheme: _theme(),
  build: (context) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'GOOGLE PLAY STORE LISTING',
        style: pw.TextStyle(
          fontSize: 9,
          color: _brand,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 1.6,
        ),
      ),
      pw.SizedBox(height: 10),
      pw.Text(
        'INO - Phone screenshots',
        style: pw.TextStyle(
          fontSize: 30,
          fontWeight: pw.FontWeight.bold,
          color: _ink,
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Text(
        'Six screens, captured at 1080 x 1920 (9:16) - the exact phone '
        'screenshot format the Play Console accepts.',
        style: const pw.TextStyle(fontSize: 11, color: _muted, lineSpacing: 3),
      ),
      pw.SizedBox(height: 22),
      pw.Container(height: 1, color: _rule),
      _h2('What is in this document'),
      _bullet(
        'One page per screenshot: the image itself, the caption to use, and '
        'why it earns its slot.',
      ),
      _bullet(
        'Step-by-step upload instructions for the Play Console, with the exact '
        'asset requirements.',
      ),
      _bullet('A pre-submission checklist for the whole Graphics section.'),
      _h2('How these were captured'),
      _body(
        'Each screen was rendered from the app source itself at exactly '
        '1080 x 1920 px, via test/playstore_screenshots.dart. Nothing was '
        'redrawn, mocked up or edited - what you see is what the widgets paint. '
        'To re-capture after a UI change:',
      ),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: _panel,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Text(
          'flutter test test/playstore_screenshots.dart --update-goldens\n'
          'dart run tool/make_screenshot_pdf.dart',
          style: pw.TextStyle(
            fontSize: 9.5,
            font: pw.Font.courier(),
            color: _ink,
            lineSpacing: 3,
          ),
        ),
      ),
      _note(
        'Read this before you upload',
        'These renders use a signed-out, empty account, so counts read 0 and '
        'some screens show their empty state ("No reminders yet", "No '
        'Documents Yet"). That is honest but it undersells the app. For the '
        'live listing, capture the same six screens on a device signed in to '
        'an account that holds a few documents, properties and reminders - '
        'then drop those files into test/screenshots/ under the same names '
        'and re-run the second command above to rebuild this PDF.',
        accent: PdfColor.fromInt(0xFFF59E0B),
      ),
      pw.Spacer(),
      pw.Text(
        'Generated ${DateTime.now().toIso8601String().split('T').first} - '
        'INO_PlayStore_Screenshots.pdf',
        style: const pw.TextStyle(fontSize: 8.5, color: _muted),
      ),
    ],
  ),
);

pw.Page _shotPage(_Shot shot, pw.MemoryImage image) => pw.Page(
  pageTheme: _theme(),
  build: (context) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: pw.BoxDecoration(
              color: _brand,
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Text(
              shot.slot.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 8,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ),
          pw.SizedBox(width: 9),
          pw.Text(
            shot.file,
            style: pw.TextStyle(
              fontSize: 8.5,
              font: pw.Font.courier(),
              color: _muted,
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 10),
      _h1(shot.screen),
      pw.SizedBox(height: 16),
      pw.Expanded(
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 232,
              decoration: pw.BoxDecoration(
                borderRadius: pw.BorderRadius.circular(10),
                border: pw.Border.all(color: _rule, width: 0.8),
              ),
              padding: const pw.EdgeInsets.all(4),
              child: pw.ClipRRect(
                horizontalRadius: 7,
                verticalRadius: 7,
                child: pw.Image(image, width: 224, height: 398),
              ),
            ),
            pw.SizedBox(width: 24),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'SUGGESTED CAPTION',
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: _teal,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text(
                    shot.caption,
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: _ink,
                      lineSpacing: 3,
                    ),
                  ),
                  pw.SizedBox(height: 16),
                  pw.Text(
                    'WHAT THIS SHOWS',
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: _teal,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  pw.SizedBox(height: 7),
                  ...shot.bullets.map(_bullet),
                  pw.SizedBox(height: 14),
                  pw.Container(height: 1, color: _rule),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    'Size 1080 x 1920 px  -  9:16  -  PNG',
                    style: const pw.TextStyle(fontSize: 9, color: _muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  ),
);

pw.Page _howToPage() => pw.Page(
  pageTheme: _theme(),
  build: (context) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _h1('Uploading these to the Play Console'),
      pw.SizedBox(height: 14),
      _numbered(
        1,
        'Open your app in the Play Console',
        'play.google.com/console -> select the INO app.',
      ),
      _numbered(
        2,
        'Go to Grow -> Store presence -> Main store listing',
        'On newer console layouts this sits under "Grow users". Pick the '
            'default language first (en-IN or en-US); other locales inherit '
            'these assets unless you override them.',
      ),
      _numbered(
        3,
        'Scroll to Graphics -> Phone screenshots',
        'Drag all six PNGs in at once, or use "Upload". Play accepts 2 to 8 '
            'phone screenshots; you need at least 2 to publish.',
      ),
      _numbered(
        4,
        'Set the order deliberately',
        'Drag the tiles so Home, My Wallets and Identity Wallet are first, '
            'second and third. Only the first 2-3 appear in Play search '
            'results, so those carry the listing.',
      ),
      _numbered(
        5,
        'Fill in the rest of the Graphics section',
        'App icon and feature graphic are both mandatory - the listing will '
            'not save without them. See the checklist on the next page.',
      ),
      _numbered(
        6,
        'Save, then submit',
        'Click Save, then go to Publishing overview and Send for review. '
            'Graphics changes go through review and typically take a few hours '
            'to a couple of days.',
      ),
      _h2('Phone screenshot requirements'),
      _bullet('PNG or JPEG.'),
      _bullet('Up to 8 MB per file.'),
      _bullet(
        'Aspect ratio 16:9 (landscape) or 9:16 (portrait). The files in this '
        'document are 9:16.',
      ),
      _bullet(
        'Each side between 320 px and 3840 px, and the long side no more than '
        'twice the short side. 1080 x 1920 satisfies all of this.',
      ),
      _bullet('Minimum 2, maximum 8.'),
      _note(
        'Tablet screenshots',
        'Not required to publish, but without them Play can mark the listing '
        '"not optimised for tablets" and rank it lower on large screens. If '
        'you want them, add 7-inch and 10-inch sets later - the same harness '
        'can render them by changing the physicalSize in '
        'test/playstore_screenshots.dart.',
      ),
      _note(
        'What Play will reject',
        'No device frames that imply a different OS, no fabricated ratings or '
        '"Editor\'s Choice" style badges, no "Download now" / "Install" calls '
        'to action inside the image, no pricing claims, and no text that is '
        'not in the listing language. Plain product screenshots like these are '
        'the safest option.',
        accent: PdfColor.fromInt(0xFFEF4444),
      ),
    ],
  ),
);

pw.Page _checklistPage() => pw.Page(
  pageTheme: _theme(),
  build: (context) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _h1('Graphics section - full checklist'),
      pw.SizedBox(height: 6),
      _body(
        'Everything the Main store listing page asks for, and the exact spec '
        'for each. The three marked required block publishing.',
      ),
      pw.SizedBox(height: 10),
      _checkRow(
        'App icon',
        'Required',
        '512 x 512 px, 32-bit PNG with alpha, max 1 MB. Source already in the '
            'repo at assets/icon/ino_icon.png.',
      ),
      _checkRow(
        'Feature graphic',
        'Required',
        '1024 x 500 px, JPEG or 24-bit PNG with no alpha channel, max 15 MB. '
            'Shown at the top of the listing and in some Play placements. Keep '
            'text away from the edges - it gets cropped on small screens.',
      ),
      _checkRow(
        'Phone screenshots',
        'Required',
        '2-8 images. The six in this document.',
      ),
      _checkRow(
        '7-inch tablet screenshots',
        'Optional',
        'Up to 8. Same format rules as phone.',
      ),
      _checkRow(
        '10-inch tablet screenshots',
        'Optional',
        'Up to 8. Same format rules as phone.',
      ),
      _checkRow(
        'Promo video',
        'Optional',
        'A YouTube URL, not an upload. Leave blank if you do not have one - an '
            'empty field is better than a weak video.',
      ),
      _h2('Also on the same page'),
      _bullet('App name - max 30 characters.'),
      _bullet(
        'Short description - max 80 characters. This is the line under the '
        'icon in search; write it last and make it concrete.',
      ),
      _bullet('Full description - max 4000 characters.'),
      _h2('Before you hit Send for review'),
      _bullet(
        'Privacy policy URL is set under Policy -> App content. The repo '
        'already has PRIVACY_POLICY.md and the ino-privacy-policy site.',
      ),
      _bullet(
        'Data safety form completed and matching what the app actually '
        'collects.',
      ),
      _bullet(
        'Account deletion URL provided - required because the app has '
        'accounts. See DELETE_ACCOUNT.md.',
      ),
      _bullet('Content rating questionnaire submitted.'),
      _bullet('Target audience and ads declarations answered.'),
      _note(
        'One last pass on the images',
        'Open each PNG full-size and check the status bar, the greeting name '
        'and any visible record for anything you would not want public - a '
        'real phone number, a real document number, a real email. Store '
        'screenshots are permanent and indexed.',
      ),
    ],
  ),
);

pw.Widget _checkRow(String title, String tag, String detail) {
  final required = tag == 'Required';
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 8),
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      color: _panel,
      borderRadius: pw.BorderRadius.circular(5),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
                color: _ink,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 2,
              ),
              decoration: pw.BoxDecoration(
                color: required
                    ? const PdfColor.fromInt(0xFFFDE8E8)
                    : const PdfColor.fromInt(0xFFE7F3EC),
                borderRadius: pw.BorderRadius.circular(3),
              ),
              child: pw.Text(
                tag.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 0.6,
                  color: required
                      ? const PdfColor.fromInt(0xFFC0392B)
                      : _teal,
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          detail,
          style: const pw.TextStyle(
            fontSize: 9.5,
            color: _muted,
            lineSpacing: 2.2,
          ),
        ),
      ],
    ),
  );
}
