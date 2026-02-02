import 'dart:html' as html;
import 'dart:js' as js;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DiscussionPage extends StatefulWidget {
  const DiscussionPage({super.key});

  @override
  State<DiscussionPage> createState() => _DiscussionPageState();
}

class _DiscussionPageState extends State<DiscussionPage> {
  String? _selectedChatId;
  String? _otherUserName;

  @override
  Widget build(BuildContext context) {
    // Récupération sécurisée de l'ID utilisateur
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? "";

    if (currentUserId.isEmpty) {
      return const Scaffold(body: Center(child: Text("Veuillez vous connecter.")));
    }

    if (_selectedChatId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Mes Discussions"),
          backgroundColor: Colors.blueAccent,
          centerTitle: true,
          elevation: 0,
        ),
        body: StreamBuilder<QuerySnapshot>(
          // UPDATE: Filtrage optimisé pour correspondre aux règles de sécurité
          stream: FirebaseFirestore.instance
              .collection('mentorships')
              .where('status', isEqualTo: 'accepted')
              .where(Filter.or(
                Filter('studentId', isEqualTo: currentUserId),
                Filter('mentorId', isEqualTo: currentUserId),
              ))
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text(
                    "Note: Si vous voyez une erreur d'index, cliquez sur le lien dans la console de debug.\n\n${snapshot.error}",
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data?.docs ?? [];

            if (docs.isEmpty) {
              return const Center(child: Text("Aucune discussion active."));
            }

            return ListView.separated(
              itemCount: docs.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                final bool isMeMentor = data['mentorId'] == currentUserId;
                
                // On affiche le nom de l'autre participant
                final String displayName = isMeMentor 
                    ? (data['studentName'] ?? "Étudiant") 
                    : (data['mentorName'] ?? "Mentor");
                
                final String otherId = isMeMentor ? data['studentId'] : data['mentorId'];
                
                // Génération du Chat ID unique (trié alphabétiquement pour la cohérence)
                final List<String> ids = [currentUserId, otherId]..sort();
                final String chatId = ids.join("_");

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    radius: 25,
                    backgroundColor: Colors.blueAccent.withOpacity(0.1),
                    child: Text(displayName[0].toUpperCase(), 
                      style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text("Cliquer pour discuter"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => setState(() { 
                    _selectedChatId = chatId; 
                    _otherUserName = displayName; 
                  }),
                );
              },
            );
          },
        ),
      );
    }

    return ChatWindow(
      chatId: _selectedChatId!,
      otherName: _otherUserName!,
      onBack: () => setState(() => _selectedChatId = null),
    );
  }
}

/* =============================================================
    FENÊTRE DE CHAT (Web & Mobile friendly)
============================================================= */
class ChatWindow extends StatefulWidget {
  final String chatId;
  final String otherName;
  final VoidCallback onBack;
  const ChatWindow({super.key, required this.chatId, required this.otherName, required this.onBack});

  @override
  State<ChatWindow> createState() => _ChatWindowState();
}

class _ChatWindowState extends State<ChatWindow> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Set<String> _hiddenMessages = {};
  bool _isRecording = false;
  dynamic _voiceListener;

  CollectionReference get messagesRef => 
    FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages');

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _voiceListener = (event) {
        final audioBase64 = (event as html.CustomEvent).detail as String;
        _sendMessage(type: 'audio', content: audioBase64);
      };
      html.window.addEventListener('voiceMessage', _voiceListener);
    }
  }

  @override
  void dispose() {
    if (kIsWeb) html.window.removeEventListener('voiceMessage', _voiceListener);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage({required String type, required String content}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || content.isEmpty) return;

    await messagesRef.add({
      'type': type,
      'content': content,
      'senderId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _deleteMessage(String messageId) async {
    try {
      await messagesRef.doc(messageId).delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Permission refusée : $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.otherName),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
        backgroundColor: Colors.blueAccent,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: messagesRef.orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text("Erreur : ${snapshot.error}"));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                final docs = snapshot.data!.docs;
                return ListView.builder(
                  reverse: true,
                  controller: _scrollController,
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final doc = docs[i];
                    if (_hiddenMessages.contains(doc.id)) return const SizedBox();
                    
                    final data = doc.data() as Map<String, dynamic>;
                    final isUser = data['senderId'] == FirebaseAuth.instance.currentUser?.uid;
                    
                    return GestureDetector(
                      onLongPress: () => _showOptions(doc.id),
                      child: _buildBubble(data, isUser),
                    );
                  },
                );
              },
            ),
          ),
          _buildInput(),
        ],
      ),
    );
  }

  void _showOptions(String messageId) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text("Supprimer pour moi"),
              onTap: () { setState(() => _hiddenMessages.add(messageId)); Navigator.pop(context); },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text("Supprimer pour tout le monde"),
              onTap: () { _deleteMessage(messageId); Navigator.pop(context); },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(Map<String, dynamic> msg, bool isUser) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? Colors.blueAccent : Colors.grey[200],
          borderRadius: BorderRadius.circular(15),
        ),
        child: msg['type'] == 'audio'
            ? IconButton(
                icon: const Icon(Icons.play_circle),
                onPressed: () => html.AudioElement(msg['content']).play(),
                color: isUser ? Colors.white : Colors.black)
            : Text(msg['content'] ?? '', 
                style: TextStyle(color: isUser ? Colors.white : Colors.black, fontSize: 16)),
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey[300]!))),
      child: Row(
        children: [
          GestureDetector(
            onLongPress: () { setState(() => _isRecording = true); js.context.callMethod("startVoice"); },
            onLongPressUp: () { setState(() => _isRecording = false); js.context.callMethod("stopVoice"); },
            child: CircleAvatar(
              backgroundColor: _isRecording ? Colors.red : Colors.blueAccent,
              child: const Icon(Icons.mic, color: Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: "Écrire...", 
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none)
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.blueAccent),
            onPressed: () {
              final text = _controller.text.trim();
              if (text.isNotEmpty) {
                _sendMessage(type: 'text', content: text);
                _controller.clear();
              }
            },
          ),
        ],
      ),
    );
  }
}