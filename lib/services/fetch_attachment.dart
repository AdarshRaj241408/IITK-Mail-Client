import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart';
import 'package:iitk_mail_client/Storage/models/message.dart';
import 'package:iitk_mail_client/services/imap_service.dart';
import 'package:logger/logger.dart'; // Import your Message model

final logger = Logger();

class FetchAttachments {
  static Future<Message> fetchMessageWithAttachments({
    required int uniqueId,
    required String username,
    required String password,
  }) async {
    try {
      MimeMessage mimeMessage = await ImapService.fetchMailByUid(
        uniqueId: uniqueId,
        username: username,
        password: password,
      );

      var infos = mimeMessage.findContentInfo();
      final inlineAttachments = mimeMessage
          .findContentInfo(disposition: ContentDisposition.inline)
          .where((info) =>
              info.fetchId.isNotEmpty &&
              !(info.isText ||
                  info.isImage ||
                  info.mediaType?.sub ==
                      MediaSubtype.messageDispositionNotification));
      infos.addAll(inlineAttachments);

      List<MimePart> mimeParts = [];

      // Fetch MIME parts corresponding to inline attachments
      for (var info in infos) {
        MimePart? mimePart = mimeMessage.getPart(info.fetchId);
        if (mimePart != null) {
          Uint8List? uint8List = mimePart.decodeContentBinary();
          logger.i("MimePart fetched");
          mimeParts.add(mimePart);
        } else {
          logger.i("Mime not fetched");
        }
      }

      return Message.fromMimeMessage(
        uniqueId: uniqueId,
        mimeMessage: mimeMessage,
        attachments: infos.toList(),
        mimeParts: mimeParts,
      );
    } catch (e) {
      logger.e('Error fetching message: $e');
      return Message.fromMimeMessage(
        uniqueId: uniqueId,
        mimeMessage: MimeMessage(),
      );
    }
  }
}
