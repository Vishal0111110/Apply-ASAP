// ignore_for_file: unnecessary_string_escapes, prefer_const_constructors

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:http/http.dart' as http;
import 'package:dart_openai/dart_openai.dart';
import 'package:url_launcher/url_launcher.dart';

import 'question_data.dart';
import 'chat_screen.dart';

class ResultScreen extends StatefulWidget {
  final QuestionData answers;

  const ResultScreen({super.key, required this.answers});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with TickerProviderStateMixin {
  late Future<ResultData> futureResult;
  late String systemString, userString;
  List<String> loadingPhrases = [
    'Working on it, one sec.',
    'I\'ll get back to you on that.',
    'Just a moment, please.',
    'Let me check on that.',
    'I\'m almost there.',
    'Hang tight.',
    'Coming right up.',
    'Well.. well that\'s interesting.',
    'I\'m on it.',
    'Be right back.',
    'Just a sec, I\'m buffering.'
  ];

  @override
  void initState() {
    super.initState();

    // Updated system prompt: now includes instruction to provide an exact job link and a YouTube courses link.
    systemString = """
You are a super thoughtful Job domains and job recommender and link provider for every type of audience.
You read data given to you in JSON format and ONLY reply in JSON format.
You recommend 20 Job domains based on the input JSON and provide:
1. A very enthusiastic and short reasoning (20 words) for each Job domain.
2. A list of 3-5 skills (with short names) that should be polished for success in that field.
3. An EXACT JOB LINK from a reputable job board I want you to atleast one valid link from joblever which is correct and job lever link scard should be first (e.g., https://jobs.lever.co/,Indeed, LinkedIn, company website etc) for job listings in that field.
4. An EXACT YouTube COURSES LINK offering free courses to improve skills in that domain.
The output should be in this exact format:
{"Job domain Name1": ["reasoning1", "Skills Required: skill1, skill2, skill3", "jobLink1", "coursesLink1"], "Job domain Name2": ["reasoning2", "Skills Required: skill1, skill2, skill3, skill4, skill5", "jobLink2", "coursesLink2"]}
""";

    userString = """
      HERE IS THE USER'S ANSWERS:
      ${widget.answers.toJson()}
    """;

    // Uncomment if you want to fetch from GPT (OpenAI):
    // futureResult = fetchResultFromGPT();

    // Fetch from Gemini by default:
    futureResult = fetchResultFromGemini();
  }

  Future<ResultData> fetchResultFromGPT() async {
    OpenAI.apiKey = await rootBundle.loadString('assets/openai.key');
    OpenAI.showLogs = true;
    OpenAI.showResponsesLogs = true;

    final systemMessage = OpenAIChatCompletionChoiceMessageModel(
      role: OpenAIChatMessageRole.system,
      content: [
        OpenAIChatCompletionChoiceMessageContentItemModel.text(systemString)
      ],
    );
    final userMessage = OpenAIChatCompletionChoiceMessageModel(
      role: OpenAIChatMessageRole.user,
      content: [
        OpenAIChatCompletionChoiceMessageContentItemModel.text(userString)
      ],
    );

    final completion = await OpenAI.instance.chat.create(
      model: 'gpt-3.5-turbo',
      messages: [systemMessage, userMessage],
      maxTokens: 500,
      temperature: 0.2,
    );

    if (completion.choices.isNotEmpty) {
      debugPrint(
          'Result: ${completion.choices.first.message.content!.first.text}');
      return ResultData.fromJson(
        completion.choices.first.message.content!.first.text.toString(),
      );
    } else {
      throw Exception('Failed to load result from GPT');
    }
  }

  Future<ResultData> fetchResultFromGemini() async {
    final apiKey = await rootBundle.loadString('assets/gemini.key');
    final endpoint =
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?alt=json&key=$apiKey";

    final response = await http.post(
      Uri.parse(endpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'system_instruction': {
          'parts': [
            {'text': 'system: $systemString'}
          ],
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': userString}
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
          'temperature': 1.2,
          'topP': 0.8,
        },
      }),
    );

    if (response.statusCode == 200) {
      final jsonResp = jsonDecode(response.body);
      final text = jsonResp['candidates'][0]['content']['parts'][0]['text'];
      debugPrint('Gemini raw text: $text');
      return ResultData.fromJson(text);
    } else {
      throw Exception('Failed to load result: ${response.body}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final clrSchm = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Job Dashboard"),
      ),
      body: Center(
        child: FutureBuilder<ResultData>(
          future: futureResult,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Column(
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
                      (i) => loadingPhrases[
                          Random().nextInt(loadingPhrases.length)],
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
                          style: TextStyle(fontSize: 20),
                        ),
                      );
                    },
                  ),
                ],
              );
            } else if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            } else {
              final data = snapshot.data;
              if (data == null || data.result.isEmpty) {
                return const Text('No data found.');
              }

              return ListView.builder(
                itemCount: data.result.length,
                itemBuilder: (context, index) {
                  final entry = data.result.entries.elementAt(index);

                  // Animate each item after a small delay.
                  return FutureBuilder(
                    future: Future.delayed(Duration(milliseconds: 200 * index)),
                    builder: (context, _) {
                      if (_.connectionState == ConnectionState.waiting) {
                        return Container();
                      } else {
                        return SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(1, 0),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: AnimationController(
                                duration: const Duration(milliseconds: 300),
                                vsync: this,
                              )..forward(),
                              curve: Curves.easeInOutSine,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ChatScreen(
                                      career: entry.key,
                                      ans: widget.answers,
                                    ),
                                  ),
                                );
                              },
                              child: Card(
                                elevation: 5,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15.0),
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        clrSchm.inversePrimary,
                                        clrSchm.secondaryContainer
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(15.0),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 25, vertical: 12),
                                    title: Text(
                                      entry.key,
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Reasoning text.
                                        Text(
                                          entry.value[0],
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                        const SizedBox(height: 8),
                                        const Divider(
                                          thickness: 2.5,
                                        ),
                                        // Skills chips.
                                        Wrap(
                                          spacing: 4,
                                          runSpacing: 2,
                                          children: [
                                            for (var skill
                                                in entry.value[1].split(','))
                                              Chip(
                                                label: Text(
                                                  skill.trim(),
                                                  style: const TextStyle(
                                                      fontSize: 10),
                                                ),
                                              ),
                                          ],
                                        ),
                                        // Display job link if available.
                                        if (entry.value.length > 2)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 8.0),
                                            child: InkWell(
                                              onTap: () async {
                                                final url = entry.value[2];
                                                if (await canLaunch(url)) {
                                                  await launch(url);
                                                } else {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(const SnackBar(
                                                          content: Text(
                                                              "Could not launch job link")));
                                                }
                                              },
                                              child: const Text(
                                                "Apply Now",
                                                style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.white,
                                                    decoration: TextDecoration
                                                        .underline),
                                              ),
                                            ),
                                          ),
                                        // Display courses link if available.
                                        if (entry.value.length > 3)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 8.0),
                                            child: InkWell(
                                              onTap: () async {
                                                final coursesUrl =
                                                    entry.value[3];
                                                if (await canLaunch(
                                                    coursesUrl)) {
                                                  await launch(coursesUrl);
                                                } else {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(const SnackBar(
                                                          content: Text(
                                                              "Could not launch courses link")));
                                                }
                                              },
                                              child: const Text(
                                                "Learn Now",
                                                style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.white,
                                                    decoration: TextDecoration
                                                        .underline),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                    },
                  );
                },
              );
            }
          },
        ),
      ),
    );
  }
}

// Updated ResultData class with JSON cleaning; now supporting job links as the third field.
class ResultData {
  final Map<String, List<String>> result;

  ResultData({required this.result});

  factory ResultData.fromJson(String jsonString) {
    jsonString = jsonString.trim();

    // Remove markdown code fences if present.
    if (jsonString.startsWith("```")) {
      final startIndex = jsonString.indexOf('{');
      final endIndex = jsonString.lastIndexOf('}');
      if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
        jsonString = jsonString.substring(startIndex, endIndex + 1);
      }
    }

    final Map<String, dynamic> rawMap = jsonDecode(jsonString);
    final resultMap = <String, List<String>>{};

    rawMap.forEach((key, value) {
      if (value is List) {
        final items = value.map((item) => item.toString()).toList();
        resultMap[key] = items;
      }
    });

    return ResultData(result: resultMap);
  }
}
