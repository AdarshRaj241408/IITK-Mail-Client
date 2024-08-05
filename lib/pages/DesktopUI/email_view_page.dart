// ignore_for_file: prefer_const_constructors

import 'dart:typed_data';
import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';
import 'package:iitk_mail_client/Storage/models/email.dart';
import 'package:iitk_mail_client/Storage/models/message.dart';
import 'package:iitk_mail_client/Storage/queries/mark_seen.dart';
import 'package:iitk_mail_client/Storage/queries/toggle_flagged_status.dart';
import 'package:iitk_mail_client/Storage/queries/toggle_trashed_status.dart';
import 'package:iitk_mail_client/pages/forward_screen.dart';
import 'package:iitk_mail_client/pages/reply_screen.dart';
import 'package:iitk_mail_client/services/download_files.dart';
import 'package:iitk_mail_client/services/fetch_attachment.dart';
import 'package:iitk_mail_client/services/open_files.dart';
import 'package:iitk_mail_client/services/imap_service.dart';
import 'package:iitk_mail_client/services/secure_storage_service.dart';
import 'package:logger/logger.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart'; 


class EmailViewPage extends StatefulWidget {
  final Email email;
  final String username;
  final String password;

  const EmailViewPage({
    super.key,
    required this.email,
    required this.username,
    required this.password,
  });

  @override
  State<EmailViewPage> createState() => _EmailViewPageState();
}

class _EmailViewPageState extends State<EmailViewPage> {
  late final String subject;
  late final String sender;
  late final String body;
  late final DateTime date;
  late final int uniqueId;
  late bool isFlagged;
  late bool isTrashed;
  final logger = Logger();
  final downloader = DownloadFiles();
  final opener = OpenFiles();
  Message? message;
  List<ContentInfo>? attachments;
  List<MimePart>? mimeParts;
  String? username;
  String? password;

  @override
  void initState() {
    super.initState();
    _setCredentials();
    subject = widget.email.subject ?? 'No Subject';
    sender = widget.email.from ?? 'Unknown Sender';
    body = widget.email.body ?? 'No Content';
    date = widget.email.receivedDate ?? DateTime.now();
    uniqueId = widget.email.uniqueId;
    isFlagged = widget.email.isFlagged;
    isTrashed = widget.email.isTrashed;
    if(widget.email.isRead==false){
      markRead();
    }
    // Fetch attachments if the email has attachments\
    if (widget.email.hasAttachment) {
      FetchAttachments.fetchMessageWithAttachments(
        uniqueId: uniqueId,
        username: widget.username,
        password: widget.password,
      ).then((Message fetchedMessage) {
        setState(() {
          message = fetchedMessage;
          attachments = fetchedMessage.attachments;
          mimeParts = fetchedMessage.mimeparts;
        });
        for (var attachment in attachments!) {
          logger.i(
              'Attachment found: ${attachment.fileName ?? 'Unnamed attachment'}');
        }
      }).catchError((error) {
        logger.e('Failed to fetch message: $error');
      });
    }
    else if(widget.email.isRead==false){
      try{
          ImapService.markRead(uniqueId: uniqueId, username: widget.username, password: widget.password);
      }
      catch(e){
        logger.i("Failed to mark the mail as read");
      }
    }
  }

  Future <void> markRead() async{
    await markSeen(widget.email.id);
  }

  Future <void> _setCredentials() async{
    username = await SecureStorageService.getUsername();
    password = await SecureStorageService.getPassword();
  }

  Future<void> _handleFlagged() async{
    try{
      await ImapService.toggleFlagged(isFlagged: isFlagged, uniqueId : uniqueId, username: username!, password: password!);
      await toggleFlaggedStatus(widget.email.id);
      setState(() {
        isFlagged = !isFlagged;
      });
    } 
    catch (e) {
      logger.i("error in changing flag status :$e");
      if(mounted){
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error occured in flagging')));
      }
    }
    
  }

  Future<void> _handleDeleted() async{
    try {
      await ImapService.toggleTrashed(isTrashed: isTrashed, uniqueId : uniqueId, username: username!, password: password!);
      await toggleTrashedStatus(widget.email.id);
      setState(() {
        isTrashed = !isTrashed;
      });
    }
    catch (e) {
      logger.i("error in changing trash status :$e");
      if(mounted){
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error occured in deleting')));
      }
    }
    
  }
  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url); // Convert String to Uri
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error occured in opening url')));
    }
  }
  bool _containsHtml(String input) {
    final htmlPattern = RegExp(r'<[^>]*>');
    return htmlPattern.hasMatch(input);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.brightness == Brightness.dark ? Colors.white70 : Colors.black87,
      fontSize: 16,
    );

    final backgroundColor =theme.scaffoldBackgroundColor ;
  
    Widget _buildRichText(String text) {
      final RegExp linkPattern = RegExp(
        r'(https?:\/\/[^\s]+)',
        caseSensitive: false,
      );

      final List<TextSpan> spans = [];
      final matches = linkPattern.allMatches(text);

      int lastMatchEnd = 0;

      for (final match in matches) {
        if (match.start > lastMatchEnd) {
          spans.add(TextSpan(text: text.substring(lastMatchEnd, match.start)));
        }
        spans.add(
          TextSpan(
            text: match.group(0),
            style: TextStyle(color: Colors.blue),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                _launchURL(match.group(0)!);
              },
          ),
        );
        lastMatchEnd = match.end;
      }

      if (lastMatchEnd < text.length) {
        spans.add(TextSpan(text: text.substring(lastMatchEnd)));
      }

      return SelectableText.rich(
        TextSpan(children: spans, style: textStyle),
      );
    }
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        actions: [
          !isTrashed
          ? IconButton(
            icon: Icon(Icons.delete_outline, color: theme.appBarTheme.iconTheme?.color),
            onPressed: () {
              _handleDeleted();
            },
          )
          : IconButton(
            icon: Icon(Icons.delete, color: theme.appBarTheme.iconTheme?.color),
            onPressed: () {
              _handleDeleted();
            }
          ),
          isFlagged
           ? IconButton(
            icon: Icon(Icons.flag, color: theme.appBarTheme.iconTheme?.color),
            onPressed: () {
              _handleFlagged();
            },
          )
          : IconButton(
            icon: Icon(Icons.flag_outlined, color: theme.appBarTheme.iconTheme?.color),
            onPressed: () {
              _handleFlagged();
            },
          )
        ],
      ),
      body: Container(
        color: theme.scaffoldBackgroundColor,
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subject,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  CircleAvatar(
                    child: Text(
                      sender[0].toUpperCase(),
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${date.day}-${date.month}-${date.year}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.brightness == Brightness.dark
                                  ? Colors.white70
                                  : Colors.grey,
                              fontSize: 14),
                        ),
                        Text(
                          sender,
                          maxLines: null,
                          overflow: TextOverflow.fade,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.brightness == Brightness.dark
                                ? Colors.white
                                : Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                ],
              ),
              SizedBox(height: 8),
              Divider(color: Colors.grey),
              //attachment
              if (widget.email.hasAttachment && attachments != null) ...[
                for (var i = 0; i < attachments!.length; i++)
                  Column(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          if (mimeParts != null && i < mimeParts!.length) {
                            final mimePart = mimeParts![i];
                            // Download the file
                            final Uint8List? fileBytes =mimePart.decodeContentBinary();
                            if (fileBytes != null) {
                              final String fileName = attachments![i].fileName ?? 'Unnamed';
                              final String? filePath =await DownloadFiles().downloadFileFromBytes(
                                  fileBytes,
                                  fileName,
                                  keepDuplicate: true,
                                );

                              // Open the file
                              if (filePath != null) {
                                await opener.open(filePath);
                              } else {
                                logger.i('Failed to download file.');
                              }
                            } else {
                              logger.i('Failed to decode attachment content.');
                            }
                          } else {
                            logger.e(
                              'MimePart or attachments list is null or out of bounds',
                            );
                          }
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.brightness == Brightness.dark
                                ? Colors.grey[800]
                                : Colors.grey[200],
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                          child: ListTile(
                            title: Text(
                              attachments![i].fileName ?? 'Unnamed',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.normal,
                                color: theme.brightness == Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                              ),
                            ),
                            trailing: IconButton(
                              icon: Icon(Icons.download),
                              onPressed: () async {
                                // Handle download action for this attachment
                                if (mimeParts != null &&
                                    i < mimeParts!.length) {
                                  final mimePart = mimeParts![i];
                                  final data = mimePart.decodeContentBinary();
                                  final fileName =
                                      attachments![i].fileName ?? 'Unnamed';
                                  final path =
                                      await downloader.downloadFileFromBytes(
                                    data!,
                                    fileName,
                                  );
                                  if (path != null) {
                                    logger.i('File downloaded to: $path');
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Downloaded to: $path',
                                        ),
                                      ),
                                    );
                                  } else {
                                    logger.e('Failed to download file');
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Failed to download file',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 5,
                      )
                    ],
                  ),
                const Divider(color: Colors.grey),
              ],
              const SizedBox(height: 8),
              // SelectableText(
              //   body,
              //   style: theme.textTheme.bodyMedium?.copyWith(
              //     color: theme.brightness == Brightness.dark
              //         ? Colors.white70
              //         : Colors.black87,
              //     fontSize: 16,
              //   ),
              // ),
              _containsHtml(body)
        ? Html(
              data: body,
              style: {
                "body": Style(
                  color: textStyle?.color,
                  fontSize: FontSize(textStyle?.fontSize ?? 16.0),
                ),
                "h1": Style(
                  fontSize: FontSize(textStyle?.fontSize ?? 16.0), 
                  backgroundColor: backgroundColor,color:  theme.brightness == Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                                    margin: Margins.all(0),
                  padding: HtmlPaddings.all(0), ),
                "h2": Style(
                  fontSize: FontSize(textStyle?.fontSize ?? 16.0), 
                  backgroundColor: backgroundColor,color:  theme.brightness == Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                                     margin: Margins.all(0),
                  padding: HtmlPaddings.all(0),
                                    ),
                "h3": Style(
                  fontSize: FontSize(textStyle?.fontSize ?? 16.0), 
                  backgroundColor: backgroundColor,color:  theme.brightness == Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                                     margin: Margins.all(0),
                  padding: HtmlPaddings.all(0),
                                    ),
                "h4": Style(
                  fontSize: FontSize(textStyle?.fontSize ?? 16.0), 
                  backgroundColor: backgroundColor,color:  theme.brightness == Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                                     margin: Margins.all(0),
                  padding: HtmlPaddings.all(0),
                                    ),
                "h5":Style(
                  fontSize: FontSize(textStyle?.fontSize ?? 16.0), 
                  backgroundColor: backgroundColor,color:  theme.brightness == Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                                     margin: Margins.all(0),
                  padding: HtmlPaddings.all(0),
                                    ),
                "h6":Style(
                  fontSize: FontSize(textStyle?.fontSize ?? 16.0), 
                  backgroundColor: backgroundColor,color:  theme.brightness == Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                                     margin: Margins.all(0),
                  padding: HtmlPaddings.all(0),
                                    ),
                "p":Style(
                  fontSize: FontSize(textStyle?.fontSize ?? 16.0), 
                  backgroundColor: backgroundColor,color:  theme.brightness == Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                                     margin: Margins.all(0),
                  padding: HtmlPaddings.all(0),
                                    ),
                "span":Style(
                  fontSize: FontSize(textStyle?.fontSize ?? 16.0), 
                  backgroundColor: backgroundColor,color:  theme.brightness == Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                                     margin: Margins.all(0),
                  padding: HtmlPaddings.all(0),
                                    ),
                "div": Style(
                  fontSize: FontSize(textStyle?.fontSize ?? 16.0), 
                  backgroundColor: backgroundColor,color:  theme.brightness == Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                                     margin: Margins.all(0),
                  padding: HtmlPaddings.all(0),
                                    ),
                                     "ul": Style(
                    margin: Margins.all(0),
                    padding: HtmlPaddings.all(0),
                  ),
                  "li": Style(
                    margin: Margins.all(0),
                    padding: HtmlPaddings.all(0),
                  ),
                  "br": Style(
                    margin: Margins.all(0),
                    padding: HtmlPaddings.all(0),
                  ),
                  "hr": Style(
                    margin: Margins.all(0),
                    padding: HtmlPaddings.all(0),
                  ),
              },
               onLinkTap: (url, __,_) {
                   if (url != null) {
              _launchURL(url);
            }
                },
            )
          : _buildRichText(body),
  
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.reply),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ReplyEmailPage(
                                email: widget.email,
                                username: widget.username,
                                password: widget.password,
                              ),
                            ),
                          );
                        },
                      ),
                      Text(
                        'Reply',
                        style: TextStyle(
                          color: theme.appBarTheme.iconTheme?.color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(
                    width: 15,
                  ),
                  Column(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.forward),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ForwardEmailPage(
                                email: widget.email,
                                username: widget.username,
                                password: widget.password,
                              ),
                            ),
                          );
                        },
                      ),
                      Text(
                        'Forward',
                        style: TextStyle(
                          color: theme.appBarTheme.iconTheme?.color,
                        ),
                      ),
                    ],
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
