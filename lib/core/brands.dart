// قاعدة العلامات التجارية المعروفة (للكشف عن الانتحال).
// - keys: كلمات تظهر داخل الدومين المنتحِل (بحروف صغيرة).
// - domains: الدومينات الرسمية. أي دومين فرعي منها يُعتبر رسميًا.
// - regional: العلامة لها دومينات إقليمية كثيرة (google.de ...) فنقبل label.cctld.
// - ambiguous: الاسم كلمة عادية (apple, orange ...) فلا نحكم بالانتحال إلا مع علامات أخرى.
// القائمة قابلة للتعديل: لو دومين رسمي ناقص ضيفه هنا.

class Brand {
  const Brand(
    this.name,
    this.keys,
    this.domains, {
    this.regional = false,
    this.ambiguous = false,
  });

  final String name;
  final List<String> keys;
  final List<String> domains;
  final bool regional;
  final bool ambiguous;
}

/// امتدادات دول تُستغل كثيرًا في الاحتيال: لا نقبلها كنطاق إقليمي رسمي
const Set<String> kAbusedCc = <String>{
  'cc', 'ws', 'pw', 'su', 'la', 'vc', 'nu', 'sh', 'gs', 'ms', 'cx', 'bz',
  'to', 'tk', 'ml', 'ga', 'cf', 'gq', 'xyz',
};

const List<Brand> kBrands = <Brand>[
  // --- دفع وبنوك ---
  Brand('PayPal', <String>['paypal'], <String>['paypal.com', 'paypal.me', 'paypalobjects.com']),
  Brand('Venmo', <String>['venmo'], <String>['venmo.com']),
  Brand('Cash App', <String>['cashapp'], <String>['cash.app']),
  Brand('Zelle', <String>['zelle'], <String>['zellepay.com']),
  Brand('Stripe', <String>['stripe'], <String>['stripe.com'], ambiguous: true),
  Brand('Wise', <String>['transferwise'], <String>['wise.com', 'transferwise.com']),
  Brand('Revolut', <String>['revolut'], <String>['revolut.com', 'revolut.me']),
  Brand('Payoneer', <String>['payoneer'], <String>['payoneer.com']),
  Brand('Western Union', <String>['westernunion'], <String>['westernunion.com']),
  Brand('Visa', <String>['visa'], <String>['visa.com', 'visa.co.uk'], ambiguous: true),
  Brand('Mastercard', <String>['mastercard'], <String>['mastercard.com', 'mastercard.us']),
  Brand('American Express', <String>['americanexpress', 'amex'], <String>['americanexpress.com', 'aexp.com']),
  Brand('Chase', <String>['chase'], <String>['chase.com', 'jpmorganchase.com', 'jpmorgan.com'], ambiguous: true),
  Brand('Bank of America', <String>['bankofamerica'], <String>['bankofamerica.com']),
  Brand('Wells Fargo', <String>['wellsfargo'], <String>['wellsfargo.com']),
  Brand('Citibank', <String>['citibank'], <String>['citibank.com', 'citi.com']),
  Brand('HSBC', <String>['hsbc'], <String>['hsbc.com', 'hsbc.co.uk'], regional: true),
  Brand('Barclays', <String>['barclays'], <String>['barclays.co.uk', 'barclays.com']),
  Brand('Santander', <String>['santander'], <String>['santander.com', 'santander.co.uk'], regional: true),
  Brand('Emirates NBD', <String>['emiratesnbd'], <String>['emiratesnbd.com']),
  Brand('Al Rajhi Bank', <String>['alrajhi'], <String>['alrajhibank.com.sa']),
  Brand('STC Pay', <String>['stcpay'], <String>['stcpay.com.sa']),
  // --- مصر والمنطقة ---
  Brand('Fawry', <String>['fawry'], <String>['fawry.com', 'fawrypay.com']),
  Brand('Vodafone', <String>['vodafone', 'vodafonecash', 'vfcash'], <String>['vodafone.com', 'vodafone.com.eg']),
  Brand('InstaPay', <String>['instapay', 'insta-pay'], <String>['instapay.eg']),
  Brand('CIB', <String>['cibeg'], <String>['cibeg.com']),
  Brand('Banque Misr', <String>['banquemisr'], <String>['banquemisr.com']),
  Brand('NBE', <String>['nbe'], <String>['nbe.com.eg']),
  Brand('QNB Al Ahli', <String>['qnbalahli', 'qnb'], <String>['qnbalahli.com'], ambiguous: true),
  Brand('Etisalat', <String>['etisalat', 'etisalatcash'], <String>['etisalat.eg', 'etisalat.com', 'eand.com']),
  Brand('Orange', <String>['orange', 'orangecash', 'orangemoney'], <String>['orange.eg', 'orange.com'], ambiguous: true),
  Brand('WE (Telecom Egypt)', <String>['telecomegypt', 'wepay'], <String>['te.eg']),
  Brand('Egypt Post', <String>['egyptpost', 'bareed'], <String>['egyptpost.gov.eg']),
  Brand('Careem', <String>['careem'], <String>['careem.com']),
  Brand('Talabat', <String>['talabat'], <String>['talabat.com']),
  Brand('Noon', <String>['noon'], <String>['noon.com'], ambiguous: true),
  Brand('Jumia', <String>['jumia'], <String>['jumia.com.eg', 'jumia.com'], regional: true),
  Brand('Bosta', <String>['bosta'], <String>['bosta.co']),
  Brand('مصلحة الضرائب المصرية', <String>['eta.gov'], <String>['eta.gov.eg']),
  Brand('التأمينات الاجتماعية', <String>['tameen', 'nosi'], <String>['tameen.gov.eg', 'nosi.gov.eg'], ambiguous: true),
  Brand('وزارة التموين', <String>['tamwin'], <String>['tamwin.gov.eg'], ambiguous: true),
  Brand('مصر للكهرباء', <String>['kahraba', 'eehc'], <String>['eehc.gov.eg'], ambiguous: true),
  // --- عملات رقمية ---
  Brand('Binance', <String>['binance'], <String>['binance.com', 'binance.us']),
  Brand('Coinbase', <String>['coinbase'], <String>['coinbase.com']),
  Brand('MetaMask', <String>['metamask'], <String>['metamask.io']),
  Brand('Trust Wallet', <String>['trustwallet'], <String>['trustwallet.com']),
  Brand('Kraken', <String>['kraken'], <String>['kraken.com'], ambiguous: true),
  Brand('Blockchain.com', <String>['blockchain'], <String>['blockchain.com'], ambiguous: true),
  Brand('Ledger', <String>['ledger'], <String>['ledger.com'], ambiguous: true),
  Brand('Trezor', <String>['trezor'], <String>['trezor.io']),
  Brand('OpenSea', <String>['opensea'], <String>['opensea.io']),
  // --- شركات التقنية ---
  Brand('Apple', <String>['apple', 'icloud'], <String>['apple.com', 'icloud.com'], ambiguous: true),
  Brand('Microsoft', <String>['microsoft', 'office365', 'onedrive'], <String>[
    'microsoft.com', 'live.com', 'office.com', 'outlook.com',
    'microsoftonline.com', 'office365.com', 'msn.com',
  ]),
  Brand('Google', <String>['google', 'gmail'], <String>[
    'google.com', 'google.com.eg', 'gmail.com', 'youtube.com', 'goo.gl',
    'googleusercontent.com', 'googleapis.com', 'gstatic.com', 'withgoogle.com',
  ], regional: true),
  Brand('Amazon', <String>['amazon'], <String>[
    'amazon.com', 'amazon.eg', 'amazon.ae', 'amazon.sa', 'amazon.co.uk',
    'amazonaws.com', 'amzn.to', 'amzn.com', 'a.co',
  ], regional: true, ambiguous: true),
  Brand('eBay', <String>['ebay'], <String>['ebay.com'], regional: true),
  Brand('Facebook', <String>['facebook'], <String>[
    'facebook.com', 'fb.com', 'fb.me', 'fb.watch', 'messenger.com', 'meta.com',
  ]),
  Brand('Instagram', <String>['instagram'], <String>['instagram.com', 'instagr.am']),
  Brand('WhatsApp', <String>['whatsapp'], <String>['whatsapp.com', 'whatsapp.net', 'wa.me']),
  Brand('Telegram', <String>['telegram'], <String>['telegram.org', 'telegram.me', 't.me']),
  Brand('TikTok', <String>['tiktok'], <String>['tiktok.com']),
  Brand('LinkedIn', <String>['linkedin'], <String>['linkedin.com', 'lnkd.in']),
  Brand('Twitter / X', <String>['twitter'], <String>['twitter.com', 'x.com', 't.co']),
  Brand('Snapchat', <String>['snapchat'], <String>['snapchat.com', 'snap.com']),
  Brand('Reddit', <String>['reddit'], <String>['reddit.com', 'redd.it', 'redditstatic.com']),
  Brand('Pinterest', <String>['pinterest'], <String>['pinterest.com', 'pin.it'], regional: true),
  Brand('Twitch', <String>['twitch'], <String>['twitch.tv']),
  Brand('GitHub', <String>['github'], <String>['github.com', 'githubusercontent.com', 'github.io', 'githubassets.com']),
  Brand('Yahoo', <String>['yahoo'], <String>['yahoo.com'], regional: true),
  Brand('Netflix', <String>['netflix'], <String>['netflix.com']),
  Brand('Spotify', <String>['spotify'], <String>['spotify.com', 'scdn.co']),
  Brand('Adobe', <String>['adobe'], <String>['adobe.com', 'adobelogin.com']),
  Brand('Dropbox', <String>['dropbox'], <String>['dropbox.com', 'dropboxusercontent.com']),
  Brand('DocuSign', <String>['docusign'], <String>['docusign.com', 'docusign.net']),
  Brand('Zoom', <String>['zoom'], <String>['zoom.us', 'zoom.com'], ambiguous: true),
  Brand('Steam', <String>['steampowered', 'steamcommunity'], <String>['steampowered.com', 'steamcommunity.com', 'steamstatic.com']),
  Brand('Discord', <String>['discord'], <String>['discord.com', 'discord.gg', 'discordapp.com']),
  Brand('Roblox', <String>['roblox'], <String>['roblox.com', 'rbxcdn.com']),
  Brand('Epic Games', <String>['epicgames'], <String>['epicgames.com', 'unrealengine.com']),
  Brand('PlayStation', <String>['playstation'], <String>['playstation.com']),
  Brand('Xbox', <String>['xbox'], <String>['xbox.com']),
  Brand('Samsung', <String>['samsung'], <String>['samsung.com'], regional: true),
  // --- تسوق وسفر وتوصيل ---
  Brand('Booking.com', <String>['booking'], <String>['booking.com'], ambiguous: true),
  Brand('Airbnb', <String>['airbnb'], <String>['airbnb.com'], regional: true),
  Brand('Uber', <String>['uber'], <String>['uber.com']),
  Brand('Walmart', <String>['walmart'], <String>['walmart.com']),
  Brand('AliExpress', <String>['aliexpress'], <String>['aliexpress.com', 'aliexpress.us']),
  Brand('Alibaba', <String>['alibaba'], <String>['alibaba.com', 'alibabagroup.com']),
  Brand('Shein', <String>['shein'], <String>['shein.com'], regional: true),
  Brand('Temu', <String>['temu'], <String>['temu.com']),
  Brand('DHL', <String>['dhl'], <String>['dhl.com'], regional: true),
  Brand('FedEx', <String>['fedex'], <String>['fedex.com'], regional: true),
  Brand('USPS', <String>['usps'], <String>['usps.com']),
  Brand('Royal Mail', <String>['royalmail'], <String>['royalmail.com']),
  Brand('Aramex', <String>['aramex'], <String>['aramex.com']),
  // --- جهات حكومية عالمية (تُنتحل كتير) ---
  Brand('IRS', <String>['irs'], <String>['irs.gov']),
  Brand('Social Security Administration', <String>['ssa'], <String>['ssa.gov'], ambiguous: true),
  Brand('GOV.UK', <String>['govuk'], <String>['gov.uk'], regional: true),
];

/// العلامة اللي المضيف ده أحد دومينتها الرسمية (أو دومين فرعي منها). null لو مفيش.
Brand? officialBrandOf(String host) {
  for (final b in kBrands) {
    for (final d in b.domains) {
      if (host == d || host.endsWith('.$d')) return b;
    }
  }
  return null;
}
