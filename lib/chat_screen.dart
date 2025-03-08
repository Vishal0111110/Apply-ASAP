// chat_screen.dart
import 'dart:math';
import 'question_data.dart';
import 'widgets.dart';
import 'package:dart_openai/dart_openai.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:http/http.dart' as http;
import 'package:markdown_widget/config/all.dart';
import 'dart:convert';
import 'package:markdown_widget/widget/markdown.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatScreen extends StatefulWidget {
  final String career;
  final QuestionData ans;

  const ChatScreen({super.key, required this.career, required this.ans});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _exportWAController = TextEditingController();
  final _exportEmailController = TextEditingController();
  var _awaitingResponse = false;
  String? _overleafUrl;
  final GlobalKey<AnimatedListState> _listKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  late final FocusNode _keyboardFocusNode;
  late final Stream<String> _loadingPhraseStream;
  final List<MessageBubble> _chatHistory = [];
  List<String> loadingPhrases = [
    'Working on it, one sec.',
    'I\'ll get back to you on that.',
    'Just a moment, please.',
    'Let me check on that.',
    'I\'m almost there.',
    'Hang tight.',
    'Coming right up.',
    'I\'m on it.',
    'Well.. well that\'s interesting.',
    'Be right back.',
    'Just a sec, I\'m buffering.'
  ];

  @override
  void initState() {
    super.initState();
    initMessage();
    _keyboardFocusNode = FocusNode();
    _loadingPhraseStream = Stream.periodic(
      const Duration(seconds: 3),
      (_) => loadingPhrases[Random().nextInt(loadingPhrases.length)],
    );
  }

  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void initMessage() async {
    setState(() => _awaitingResponse = true);
    String response = await fetchResultFromGemini(
        'Why was I recommended the career [${widget.career}]');
    setState(() {
      _addMessage(response, false);
      _awaitingResponse = false;
    });
  }

  void _addMessage(String response, bool isUserMessage) {
    _chatHistory
        .add(MessageBubble(content: response, isUserMessage: isUserMessage));
    final chatHistoryJson = _chatHistory.map((bubble) {
      return {"content": bubble.content, "isUserMessage": bubble.isUserMessage};
    }).toList();
    debugPrint('Chat history: $chatHistoryJson');
    try {
      _listKey.currentState!.insertItem(_chatHistory.length - 1);
    } catch (e) {
      debugPrint(e.toString());
    }
    // Scroll to the bottom of the list
    // Schedule the scroll after the frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _onSubmitted(String message) async {
    _messageController.clear();
    setState(() {
      _addMessage(message, true);
      _awaitingResponse = true;
      _overleafUrl = null; // Reset any previous URL.
    });

    final result = await fetchResultFromGemini(message);
    setState(() {
      _addMessage(result, false);
      _awaitingResponse = false;
    });

    // Check if the result appears to be LaTeX code.
    if (_isLatex(result)) {
      // Encode the LaTeX code using Base64.
      final base64Latex = base64Encode(utf8.encode(result));
      // Create the Overleaf URL using the data URL method.
      final overleafUrl =
          'https://www.overleaf.com/docs?snip_uri=data:application/x-tex;base64,$base64Latex';

      // Save the URL in the state.
      setState(() {
        _overleafUrl = overleafUrl;
      });
    }
  }

  /// A simple heuristic to check if the text is LaTeX code.
  bool _isLatex(String text) {
    return text.contains(r'\documentclass') ||
        text.contains(r'\begin{document}');
  }

  /// A simple heuristic to check for LaTeX code.

  Future<String> extractTextFromBytes(
      Uint8List bytes, String? extension) async {
    if (extension == null) return "Unsupported file format.";

    if (extension.toLowerCase() == 'pdf') {
      try {
        // Load the PDF document from the in-memory bytes.
        PdfDocument document = PdfDocument(inputBytes: bytes);
        // Create a PdfTextExtractor instance to extract text from the document.
        PdfTextExtractor extractor = PdfTextExtractor(document);
        // Extract all text from the document.
        String extractedText = extractor.extractText();
        // Dispose of the document to free up resources.
        document.dispose();
        return extractedText;
      } catch (e) {
        return "Error extracting PDF text: $e";
      }
    } else {
      return "Unsupported file format.";
    }
  }

  Future<String> fetchResultFromGPT(String career) async {
    OpenAI.apiKey = await rootBundle.loadString('assets/openai.key');
    OpenAI.showLogs = true;
    OpenAI.showResponsesLogs = true;

    final prompt =
        "Hello! I'm interested in learning more about $career. Can you tell me more about the career and provide some suggestions on what I should learn first?";

    final completion = await OpenAI.instance.chat.create(
      model: 'gpt-3.5-turbo',
      messages: [
        OpenAIChatCompletionChoiceMessageModel(
          role: OpenAIChatMessageRole.user,
          content: [
            OpenAIChatCompletionChoiceMessageContentItemModel.text(prompt)
          ],
        ),
      ],
      maxTokens: 150,
      temperature: 0.7,
    );

    if (completion.choices.isNotEmpty) {
      return completion.choices.first.message.content!.first.text.toString();
    } else {
      throw Exception('Failed to load result');
    }
  }

  Future<String> fetchResultFromGemini(String message) async {
    final apiKey = await rootBundle.loadString('assets/gemini.key');
    final endpoint =
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?alt=sse&key=$apiKey";

    // Build chat history (assuming _chatHistory is defined elsewhere)
    final chatHistory =
        _chatHistory.map((bubble) => {"content": bubble.content}).toList();
    if (chatHistory.isEmpty) chatHistory.add({"content": message});

    final response = await http.post(
      Uri.parse(endpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'system_instruction': {
          'parts': [
            {
              'text': '''
You are Friday, a very friendly, career recommendation bot who helps students pick the best career for them. You are trained to reject answering questions that are too off-topic and to reply in under 100-160 words unless more detail is required.

You are chatting with a person who is interested in the career ["${widget.career}"] and will speak only regarding it. Base your responses on the survey JSON data provided below:
${widget.ans.toJson()}

Depending on the student's request:

• If the student asks for career suggestions or advice, provide clear and concise guidance in markdown with all publicly available resources links.

• If the student requests a tailored resume or modified resume or updated resume or changes in resume or anything related to resume, generate a Basic level latex code WITH ALL PROPER FORMATTING FONTS ALIGNMENT AND EXTREMELY PROFFESIONAL  with divider line between these field containing all the relevant resume details—including personal information, objective, education, work experience, skills, certifications, projects, achievements, and references—using the structure outlined belowand tailor or modify update or change that resume accoding to job domain and job links . output LaTeX codeONLY NOT EVEN ANY SINGLE LINE OF TEXT OTHER THAN THAT. The following LaTeX template:
IF student asks for ats score or resume review u have to out put that ats score and give suggestions only to maximize it.


'''
            }
          ],
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': message}
            ],
          },
        ],
        'safetySettings': [
          {'category': 'HARM_CATEGORY_HARASSMENT', 'threshold': 'BLOCK_NONE'},
          {'category': 'HARM_CATEGORY_HATE_SPEECH', 'threshold': 'BLOCK_NONE'},
          {
            'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
            'threshold': 'BLOCK_NONE'
          },
          {
            'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
            'threshold': 'BLOCK_NONE'
          },
        ],
        'generationConfig': {
          'candidateCount': 1,
          'temperature': 0.7,
          'topP': 0.8,
        },
      }),
    );

    debugPrint("Chat history: $chatHistory");
    if (response.statusCode == 200) {
      // Process SSE response by splitting the response body into lines,
      // filtering those that begin with "data:" and joining them together.
      final lines = response.body.split('\n');
      final dataLines =
          lines.where((line) => line.startsWith("data:")).toList();
      final resultText =
          dataLines.map((line) => line.replaceFirst("data: ", "")).join('');
      debugPrint("Result text: $resultText");

      try {
        final jsonResponse = jsonDecode(resultText);
        debugPrint('Response JSON: $jsonResponse');
        final candidateText =
            jsonResponse['candidates'][0]['content']['parts'][0]['text'];
        return candidateText;
      } catch (e) {
        debugPrint("Error decoding JSON: $e");
        return 'Error decoding response: ${response.body}';
      }
    } else {
      return 'Status [${response.statusCode}]\nFailed to load result: ${response.body}';
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    final clrSchm = Theme.of(context).colorScheme;
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Talk to Friday"),
        backgroundColor: clrSchm.primaryContainer.withOpacity(0.2),
        actions: [
          IconButton(
            icon: Icon(Icons.share, color: clrSchm.onPrimary),
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('Share Chat'),
                    content: const Text(
                        'How would you like to share your conversation?'),
                    actions: [
                      TextField(
                        controller: _exportWAController,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: textFormDecoration(
                          "Share Via WhatsApp",
                          "Enter your WA Number",
                          Icons.message_outlined,
                          context: context,
                        ).copyWith(
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.send),
                            onPressed: () async {
                              String number = _exportWAController.text;
                              if (!number.startsWith('966'))
                                number = '966$number';
                              if (![9, 12].contains(number.length)) return;
                              Navigator.of(context).pop();
                              String chatHistory = _chatHistory
                                  .map((message) =>
                                      '${message.isUserMessage ? '*You*: ' : '*Nero*: '}${message.content}')
                                  .join('\n\n');
                              await launchUrlString(
                                'https://wa.me/$number?text=${Uri.encodeComponent(chatHistory)}',
                              );
                            },
                          ),
                        ),
                      ),
                      const Padding(padding: EdgeInsets.only(top: 24)),
                      TextField(
                        controller: _exportEmailController,
                        inputFormatters: [
                          FilteringTextInputFormatter.deny(RegExp(' '))
                        ],
                        decoration: textFormDecoration(
                          "Share Via Email",
                          "Enter your Email Address",
                          Icons.email_outlined,
                          context: context,
                        ).copyWith(
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.send),
                            onPressed: () async {
                              String mail = _exportEmailController.text;
                              if (!mail.contains(RegExp(r'@\w+\.\w+.*$')))
                                return;
                              String chatHistory = _chatHistory
                                  .map((message) =>
                                      '${message.isUserMessage ? '*You*: ' : '*Friday*: '}${message.content}')
                                  .join('\n\n');
                              await launchUrlString(
                                'mailto:$mail?subject=Career Rec! Chat History&body=${Uri.encodeComponent(chatHistory)}',
                              );
                            },
                          ),
                        ),
                      ),
                      const Padding(padding: EdgeInsets.only(top: 16)),
                      TextButton(
                        child: const Text('Cancel'),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
      body: _chatHistory.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Expanded(
                      child: AnimatedList(
                        key: _listKey,
                        controller: _scrollController,
                        initialItemCount: _chatHistory.length,
                        itemBuilder: (context, index, animation) {
                          return SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(1, 0),
                              end: Offset.zero,
                            ).animate(animation),
                            child: _chatHistory[index],
                          );
                        },
                      ),
                    ),
                    // "Open in Overleaf" link appears if _overleafUrl is not null.
                    if (_overleafUrl != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: GestureDetector(
                          onTap: () async {
                            final url = _overleafUrl!;
                            if (await canLaunch(url)) {
                              await launch(url);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content:
                                        Text('Could not launch Overleaf URL.')),
                              );
                            }
                          },
                          child: Text(
                            "Open in Overleaf",
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: clrSchm.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12.0),
                        border: Border.all(color: clrSchm.secondary, width: 1),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: !_awaitingResponse
                                ? TextField(
                                    controller: _messageController,
                                    minLines: 1,
                                    maxLines: 5,
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (value) {
                                      if (value.trim().isNotEmpty) {
                                        _onSubmitted(value.trim());
                                        _messageController.clear();
                                      }
                                    },
                                    decoration: InputDecoration(
                                      hintText:
                                          'What would you like to know...',
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12.0),
                                      ),
                                      prefixIcon: Icon(
                                        Icons.question_answer,
                                        color: Colors.blue,
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          Icons.attach_file,
                                          color: Colors.blue,
                                        ),
                                        onPressed: () async {
                                          FilePickerResult? result =
                                              await FilePicker.platform
                                                  .pickFiles(
                                            type: FileType.custom,
                                            allowedExtensions: [
                                              'pdf',
                                              'doc',
                                              'docx'
                                            ],
                                            withData: true,
                                          );
                                          if (result != null) {
                                            final file = result.files.single;
                                            if (file.bytes != null) {
                                              String extractedText =
                                                  await extractTextFromBytes(
                                                      file.bytes!,
                                                      file.extension);
                                              _messageController.text =
                                                  "${_messageController.text}\n$extractedText";
                                            }
                                          }
                                        },
                                      ),
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: SpinKitPouringHourGlassRefined(
                                          color: clrSchm.primary,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: StreamBuilder<String>(
                                          stream: _loadingPhraseStream,
                                          builder: (context, snapshot) {
                                            final phrase = snapshot.data ??
                                                loadingPhrases.first;
                                            return AnimatedSwitcher(
                                              duration: const Duration(
                                                  milliseconds: 300),
                                              transitionBuilder:
                                                  (child, animation) {
                                                return FadeTransition(
                                                  opacity: animation,
                                                  child: ScaleTransition(
                                                    scale: animation,
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: child,
                                                  ),
                                                );
                                              },
                                              child: Text(
                                                phrase,
                                                key: ValueKey<String>(phrase),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          IconButton(
                            onPressed: !_awaitingResponse
                                ? () {
                                    final text = _messageController.text.trim();
                                    if (text.isNotEmpty) {
                                      _onSubmitted(text);
                                      _messageController.clear();
                                    }
                                  }
                                : null,
                            icon: Icon(Icons.send, color: clrSchm.primary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                [
                  SpinKitPouringHourGlassRefined(
                      color: clrSchm.primary, size: 120),
                  SpinKitDancingSquare(color: clrSchm.primary, size: 120),
                  SpinKitSpinningLines(color: clrSchm.primary, size: 120),
                  SpinKitPulsingGrid(color: clrSchm.primary, size: 120)
                ][Random().nextInt(4)],
                const SizedBox(height: 10),
                StreamBuilder<String>(
                  stream: Stream.periodic(
                    const Duration(seconds: 3),
                    (i) =>
                        loadingPhrases[Random().nextInt(loadingPhrases.length)],
                  ),
                  builder: (context, snapshot) {
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder:
                          (Widget child, Animation<double> animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SizeTransition(
                            sizeFactor: animation,
                            axis: Axis.horizontal,
                            axisAlignment: -1,
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        snapshot.data ??
                            loadingPhrases[
                                Random().nextInt(loadingPhrases.length)],
                        key: ValueKey<String>(
                          snapshot.data ??
                              loadingPhrases[
                                  Random().nextInt(loadingPhrases.length)],
                        ),
                        style: const TextStyle(fontSize: 20),
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final String content;
  final bool isUserMessage;

  const MessageBubble({
    required this.content,
    required this.isUserMessage,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isUserMessage
            ? themeData.colorScheme.secondary.withOpacity(0.4)
            : themeData.colorScheme.primary.withOpacity(0.4),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  isUserMessage ? 'You' : 'Friday',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            MarkdownWidget(
                data: content,
                shrinkWrap: true,
                config: MarkdownConfig.darkConfig),
          ],
        ),
      ),
    );
  }
}
