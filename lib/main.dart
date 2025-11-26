import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:translator/translator.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:flutter/services.dart'; // Added for clipboard functionality
import 'package:file_picker/file_picker.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(TranslationApp(cameras: cameras));
}

class TranslationApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  TranslationApp({required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Translator',
      theme: ThemeData.light().copyWith(
        primaryColor: Colors.pink,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontFamily: 'Times New Roman',
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.pink,
          ),
          iconTheme: IconThemeData(color: Colors.pink),
        ),
        textTheme: TextTheme(
          bodyLarge: TextStyle(
            fontFamily: 'Times New Roman',
            fontSize: 16,
            color: Colors.white,
          ),
          bodyMedium: TextStyle(
            fontFamily: 'Times New Roman',
            fontSize: 16,
            color: Colors.black,
          ),
          titleLarge: TextStyle(
            fontFamily: 'Times New Roman',
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.pink,
          ),
        ),
      ),
      home: TranslationPage(cameras: cameras),
    );
  }
}

class TranslationPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  TranslationPage({required this.cameras});

  @override
  _TranslationPageState createState() => _TranslationPageState();
}

class _TranslationPageState extends State<TranslationPage> {
  final TextEditingController _textController = TextEditingController();
  String _translatedText = "";
  String _inputText = "";
  String _selectedInputLanguage = 'en'; // Default: English
  String _selectedOutputLanguage = 'ta'; // Default: Tamil
  final translator = GoogleTranslator();
  final FlutterTts flutterTts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _isLoading = false;
  List<String> _favorites = [];
  late CameraController _cameraController;
  bool _isCameraReady = false;
  bool _isCameraPreview = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _speech.initialize().then((value) {
      print("Speech recognition initialized: $value");
    });
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      if (widget.cameras.isEmpty) {
        print("No cameras available");
        return;
      }
      
      _cameraController = CameraController(
        widget.cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
          orElse: () => widget.cameras.first,
        ),
        ResolutionPreset.medium,
      );
      
      await _cameraController.initialize();
      
      if (!mounted) return;
      setState(() {
        _isCameraReady = true;
      });
    } catch (e) {
      print("Camera initialization error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Camera initialization failed: $e")),
        );
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _cameraController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    await Permission.microphone.request();
    await Permission.camera.request();
    await Permission.storage.request();
  }

  Future<void> _translateText() async {
    if (_inputText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please enter or provide text for translation")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final translation = await translator.translate(
        _inputText,
        to: _selectedOutputLanguage,
      );
      setState(() {
        _translatedText = translation.text;
      });

      await _speakText(_translatedText, _selectedOutputLanguage);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Translation error: $e")),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _speakText(String text, String languageCode) async {
    await flutterTts.setLanguage(languageCode);
    await flutterTts.speak(text);
  }

  void _startListening() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() {
        _isListening = true;
      });
      _speech.listen(
        onResult: (result) {
          setState(() {
            _inputText = result.recognizedWords;
            _textController.text = _inputText;
          });
        },
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Speech recognition not available")),
      );
    }
  }

  void _stopListening() {
    _speech.stop();
    setState(() {
      _isListening = false;
    });
  }

  Future<void> _captureTextFromCamera() async {
    if (!_isCameraReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Camera is not ready")),
      );
      return;
    }

    setState(() {
      _isCameraPreview = true;
    });
  }

  Future<void> _takePicture() async {
    if (!_isCameraReady || !_isCameraPreview) return;

    try {
      final XFile image = await _cameraController.takePicture();
      final textRecognizer = GoogleMlKit.vision.textRecognizer();
      final inputImage = InputImage.fromFilePath(image.path);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

      setState(() {
        _inputText = recognizedText.text;
        _textController.text = _inputText;
        _isCameraPreview = false;
      });
      
      await _translateText();
      textRecognizer.close();
    } catch (e) {
      print("Error taking picture: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error capturing text: $e")),
      );
    }
  }

  void _addToFavorites() {
    if (_translatedText.isEmpty) return;
    
    setState(() {
      _favorites.add(_translatedText);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Added to favorites")),
    );
  }

  void _shareTranslation() {
    if (_translatedText.isEmpty) return;
    Share.share(_translatedText);
  }

Future<void> saveFile(String content) async {
  try {
    // Let user pick a directory to save the file
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory == null) {
      // User canceled the picker
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save cancelled')),
      );
      return;
    }

    // Create filename with timestamp
    final filename = 'translation_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.txt';
    final filePath = path.join(selectedDirectory, filename);
    final file = File(filePath);

    // Write file and verify it was saved
    await file.writeAsString(content);
    if (!await file.exists()) {
      throw Exception('File was not created');
    }

    // Show success message with path
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved successfully'),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () async {
            if (await file.exists()) {
              // Use share to open file location
              await Share.shareXFiles([XFile(file.path)],
                  text: 'Translation saved at ${file.path}');
            }
          },
        ),
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to save: ${e.toString()}')),
    );
    debugPrint('Save error: $e');
  }
}

  void _viewFavorites() {
    print('Saving translation...');
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Favorites"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _favorites.map((favorite) => 
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(favorite),
                )).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Close"),
            ),
          ],
        );
      },
    );
  }

  void _clearTranslatedContent() {
    setState(() {
      _translatedText = "";
      _inputText = "";
      _textController.clear();
    });
  }

  Future<void> _copyToClipboard() async {
    if (_translatedText.isEmpty) return;
    
    await Clipboard.setData(ClipboardData(text: _translatedText));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Copied to clipboard")),
    );
  }

  Widget _buildNeumorphicIcon(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
            offset: Offset(4, 4),
          ),
          BoxShadow(
            color: Colors.white,
            blurRadius: 10,
            spreadRadius: 2,
            offset: Offset(-4, -4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.pink),
        onPressed: onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Smart Translator"),
        actions: [
          _buildNeumorphicIcon(Icons.favorite, _viewFavorites),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Row(
                children: [
                  DropdownButton<String>(
                    value: _selectedInputLanguage,
                    items: [
                      DropdownMenuItem(
                        value: 'en',
                        child: Text(
                          "English",
                          style: TextStyle(color: Colors.pink),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'ta',
                        child: Text(
                          "Tamil",
                          style: TextStyle(color: Colors.pink),
                        ),
                      ),
                      DropdownMenuItem(value: 'ar', child: Text("Arabic", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'bn', child: Text("Bengali", style: TextStyle(color: Colors.pink))),
                      
                      DropdownMenuItem(value: 'fr', child: Text("French", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'de', child: Text("German", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'gu', child: Text("Gujarati", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'hi', child: Text("Hindi", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'it', child: Text("Italian", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'ja', child: Text("Japanese", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'kn', child: Text("Kannada", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'ko', child: Text("Korean", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'ml', child: Text("Malayalam", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'mr', child: Text("Marathi", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'pt', child: Text("Portuguese", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'ru', child: Text("Russian", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'es', child: Text("Spanish", style: TextStyle(color: Colors.pink))),
                      
                      DropdownMenuItem(value: 'te', child: Text("Telugu", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'tr', child: Text("Turkish", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'ur', child: Text("Urdu", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'zh-cn', child: Text("Chinese (Simplified)", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'zh-tw', child: Text("Chinese (Traditional)", style: TextStyle(color: Colors.pink)))
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedInputLanguage = val!;
                      });
                    },
                    style: TextStyle(color: Colors.pink),
                    dropdownColor: Colors.white,
                  ),
                  Spacer(),
                  DropdownButton<String>(
                    value: _selectedOutputLanguage,
                    items: [
                      DropdownMenuItem(
                        value: 'en',
                        child: Text(
                          "English",
                          style: TextStyle(color: Colors.pink),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'ta',
                        child: Text(
                          "Tamil",
                          style: TextStyle(color: Colors.pink),
                        ),
                      ),
                       DropdownMenuItem(value: 'ar', child: Text("Arabic", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'bn', child: Text("Bengali", style: TextStyle(color: Colors.pink))),
                      
                      DropdownMenuItem(value: 'fr', child: Text("French", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'de', child: Text("German", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'gu', child: Text("Gujarati", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'hi', child: Text("Hindi", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'it', child: Text("Italian", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'ja', child: Text("Japanese", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'kn', child: Text("Kannada", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'ko', child: Text("Korean", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'ml', child: Text("Malayalam", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'mr', child: Text("Marathi", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'pt', child: Text("Portuguese", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'ru', child: Text("Russian", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'es', child: Text("Spanish", style: TextStyle(color: Colors.pink))),
                      
                      DropdownMenuItem(value: 'te', child: Text("Telugu", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'tr', child: Text("Turkish", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'ur', child: Text("Urdu", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'zh-cn', child: Text("Chinese (Simplified)", style: TextStyle(color: Colors.pink))),
                      DropdownMenuItem(value: 'zh-tw', child: Text("Chinese (Traditional)", style: TextStyle(color: Colors.pink)))
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedOutputLanguage = val!;
                      });
                    },
                    style: TextStyle(color: Colors.pink),
                    dropdownColor: Colors.white,
                  ),
                ],
              ),
              SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.pink.withOpacity(0.2),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: TextField(
                  controller: _textController,
                  decoration: InputDecoration(
                    labelText: "Enter text",
                    labelStyle: TextStyle(color: Colors.white),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _inputText = value;
                    });
                  },
                ),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _translateText,
                child: Text("Translate"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pink,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              SizedBox(height: 20),
              Wrap(
                spacing: 10,
                children: [
                  _buildNeumorphicIcon(Icons.camera, _captureTextFromCamera),
                  _buildNeumorphicIcon(
                    _isListening ? Icons.stop : Icons.mic,
                    _isListening ? _stopListening : _startListening,
                  ),
                ],
              ),
              SizedBox(height: 20),
              _isLoading
                  ? CircularProgressIndicator()
                  : Column(
                      children: [
                        if (_translatedText.isNotEmpty) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Translated Text:",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              IconButton(
                                icon: Icon(Icons.copy, color: Colors.pink),
                                onPressed: _copyToClipboard,
                              ),
                            ],
                          ),
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.pink.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _translatedText,
                              style: TextStyle(fontSize: 18, color: Colors.pink),
                            ),
                          ),
                        ],
                      ],
                    ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildNeumorphicIcon(Icons.favorite, _addToFavorites),
                  _buildNeumorphicIcon(Icons.share, _shareTranslation),
                  _buildNeumorphicIcon(Icons.save, () => saveFile(_translatedText)),
                  _buildNeumorphicIcon(Icons.clear, _clearTranslatedContent),
                ],
              ),
              if (_isCameraPreview && _isCameraReady)
                Container(
                  height: 300,
                  margin: EdgeInsets.only(top: 20),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.pink, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CameraPreview(_cameraController),
                  ),
                ),
              if (_isCameraPreview)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: _takePicture,
                      child: Text("Capture Text"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.pink,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    SizedBox(width: 20),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _isCameraPreview = false;
                        });
                      },
                      child: Text("Close Camera"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}