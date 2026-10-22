import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../../../models/customer.dart';
import '../../../widgets/common/app_card.dart';
import '../../../widgets/common/detail_widgets.dart';

/// Contact and company details, each field with a copy icon; the social-media
/// value renders as a link opening in a new tab. A free-text description sits
/// below when there is one.
class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key, required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fields = <DetailField>[
      DetailField('Customer ID', customer.id, Icons.badge_outlined),
      DetailField('Business Type', customer.businessType, Icons.category_outlined),
      DetailField('Company Size', customer.size.label, Icons.groups_outlined),
      DetailField('Contact No', customer.contactNo, Icons.phone_outlined),
      DetailField('Email', customer.email, Icons.mail_outline),
      DetailField('Location', customer.location, Icons.location_on_outlined),
      DetailField('Social Media', customer.socialMedia, Icons.public,
          isLink: true),
    ];

    return SectionCard(
      title: 'Profile',
      subtitle: 'Contact and company details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailGrid(fields: fields),
          if (customer.description.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: t.surfaceAlt,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Description',
                          style:
                              TextStyle(fontSize: 12, color: t.textSecondary)),
                      CopyButton(
                          label: 'description', value: customer.description),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(customer.description,
                      style: const TextStyle(height: 1.5)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
