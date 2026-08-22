class PublicReleaseLink {
  const PublicReleaseLink({
    required this.title,
    required this.url,
    required this.description,
  });

  final String title;
  final String url;
  final String description;

  Uri get uri => Uri.parse(url);
}

class PublicReleaseLinks {
  static const siteBaseUrl = 'https://app.ourgalaxy.space';

  static const supportUrl = '$siteBaseUrl/support/';
  static const reportAbuseUrl = '$siteBaseUrl/report-abuse/';
  static const privacyUrl = '$siteBaseUrl/privacy/';
  static const termsUrl = '$siteBaseUrl/terms/';
  static const accountDeletionUrl = '$siteBaseUrl/account-deletion/';
  static const communityGuidelinesUrl = '$siteBaseUrl/community-guidelines/';
  static const sourceUrl = '$siteBaseUrl/source/';
  static const feedbackUrl = '$siteBaseUrl/feedback/';
  static const thirdPartyNoticesUrl = '$siteBaseUrl/third-party-notices/';

  static const support = PublicReleaseLink(
    title: 'Support',
    url: supportUrl,
    description: 'App help, contact, and support routing.',
  );

  static const reportAbuse = PublicReleaseLink(
    title: 'Report Abuse',
    url: reportAbuseUrl,
    description: 'Safety reporting and homeserver abuse-routing guidance.',
  );

  static const privacy = PublicReleaseLink(
    title: 'Privacy Policy',
    url: privacyUrl,
    description:
        'Privacy posture for Matrix, media, diagnostics, and services.',
  );

  static const terms = PublicReleaseLink(
    title: 'Terms / EULA',
    url: termsUrl,
    description: 'App terms and user responsibilities.',
  );

  static const accountDeletion = PublicReleaseLink(
    title: 'Account Deletion',
    url: accountDeletionUrl,
    description: 'Matrix account deletion and device sign-out boundaries.',
  );

  static const communityGuidelines = PublicReleaseLink(
    title: 'Community Guidelines',
    url: communityGuidelinesUrl,
    description: 'Community safety expectations and moderation boundaries.',
  );

  static const source = PublicReleaseLink(
    title: 'Source Offer',
    url: sourceUrl,
    description: 'Source code, license, and fork attribution information.',
  );

  static const feedback = PublicReleaseLink(
    title: 'Send Feedback',
    url: feedbackUrl,
    description: 'Feature requests, usability feedback, and general feedback.',
  );

  static const thirdPartyNotices = PublicReleaseLink(
    title: 'Third-Party Notices',
    url: thirdPartyNoticesUrl,
    description: 'Third-party notices, licenses, and asset provenance.',
  );

  static const policyLinks = <PublicReleaseLink>[
    privacy,
    terms,
    communityGuidelines,
    reportAbuse,
    accountDeletion,
    support,
    source,
    thirdPartyNotices,
  ];
}
