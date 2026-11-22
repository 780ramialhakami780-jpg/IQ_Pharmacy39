import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class StartupManager {
  static const int currentBuildNumber = 102;
  static bool _checkedThisSession = false;

  /// نافذة تأكيد الخروج بتصميم مطابق للصورة ومتناسق مع ثيم التطبيق
  static Future<bool> showExitDialog(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E2025) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF1A1C1E);
    final bodyColor = isDark ? const Color(0xFFB0B3B8) : const Color(0xFF5F6368);
    final dividerColor = isDark ? Colors.white12 : Colors.black12;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (ctx) => Dialog(
        backgroundColor: cardColor,
        elevation: 8,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 26),
            Text(
              'تأكيد!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'هل تريد الخروج من تطبيق\nIQ_Pharmacy39؟',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.55,
                  color: bodyColor,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Divider(height: 1, thickness: 1, color: dividerColor),
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: const BorderRadius.only(
                        bottomRight: Radius.circular(18),
                      ),
                      onTap: () => Navigator.of(ctx).pop(true),
                      child: Center(
                        child: Text(
                          'حسناً',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: titleColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  VerticalDivider(width: 1, thickness: 1, color: dividerColor),
                  Expanded(
                    child: InkWell(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(18),
                      ),
                      onTap: () => Navigator.of(ctx).pop(false),
                      child: Center(
                        child: Text(
                          'إلغاء',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: bodyColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      SystemNavigator.pop();
      return true;
    }
    return false;
  }

  /// فحص التحديث الإجباري والإعلان التلقائي عند فتح التطبيق
  static Future<void> checkOnStartup(BuildContext context) async {
    if (_checkedThisSession) return;
    _checkedThisSession = true;

    try {
      final config = await Supabase.instance.client
          .from('app_remote_config')
          .select()
          .eq('id', 1)
          .maybeSingle()
          .timeout(const Duration(seconds: 6));

      if (config == null || !context.mounted) return;

      final int minBuild = int.tryParse(config['min_build_number'].toString()) ?? currentBuildNumber;
      if (currentBuildNumber < minBuild) {
        final String title = (config['update_title'] ?? 'تحديث إجباري').toString();
        final String message = (config['update_message'] ?? 'يتوفر إصدار جديد من التطبيق.').toString();
        final String url = (config['update_url'] ?? '').toString();

        if (!context.mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => PopScope(
            canPop: false,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: Row(
                children: [
                  const Icon(Icons.system_update_rounded, color: Colors.teal, size: 28),
                  const SizedBox(width: 10),
                  Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
              content: Text(message, style: const TextStyle(height: 1.5)),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('تحديث الآن', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      if (url.isNotEmpty) {
                        final uri = Uri.tryParse(url);
                        if (uri != null) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        );
        return;
      }

      final bool popupEnabled = config['popup_enabled'] == true;
      if (popupEnabled) {
        final int popupVersion = int.tryParse(config['popup_version'].toString()) ?? 1;
        final prefs = await SharedPreferences.getInstance();
        final int lastSeenVersion = prefs.getInt('seen_popup_version') ?? 0;

        if (popupVersion > lastSeenVersion) {
          await prefs.setInt('seen_popup_version', popupVersion);
          final String pTitle = (config['popup_title'] ?? 'إعلان').toString();
          final String pBody = (config['popup_body'] ?? '').toString();
          final String pImage = (config['popup_image_url'] ?? '').toString();

          if (!context.mounted) return;
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: Text(pTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (pImage.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          pImage,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (pBody.isNotEmpty) Text(pBody, style: const TextStyle(height: 1.5)),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('حسناً، فهمت', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
      }
    } catch (_) {}
  }
}
