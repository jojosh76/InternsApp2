import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RequestsPage extends StatelessWidget {
  const RequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Gestion Mentorat"),
          backgroundColor: Colors.blueAccent,
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.pending_actions), text: "En attente"),
              Tab(icon: Icon(Icons.history), text: "Historique"),
            ],
            indicatorColor: Colors.white,
          ),
        ),
        // --- INTEGRATION DE LA SIDEBAR (DRAWER) ---
        drawer: Drawer(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                color: Colors.blueAccent,
                child: const SafeArea(
                  child: Text(
                    "Menu Apprentissage",
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.dashboard, color: Colors.blueAccent),
                title: const Text("Dashboard"),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.message, color: Colors.blueAccent),
                title: const Text("Discussion"),
                onTap: () {},
              ),
              ListTile(
                leading: const Icon(Icons.notifications, color: Colors.blueAccent),
                title: const Text("Demandes Mentorat"),
                selected: true, // Indique qu'on est sur cette page
                onTap: () => Navigator.pop(context),
              ),
              const Spacer(),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: const Text("Déconnexion"),
                onTap: () => FirebaseAuth.instance.signOut(),
              ),
            ],
          ),
        ),
        // --- FIN DE LA SIDEBAR ---
        body: TabBarView(
          children: [
            _buildRequestList(currentUser?.uid, ['pending'], true),
            _buildRequestList(currentUser?.uid, ['accepted', 'rejected'], false),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestList(String? mentorId, List<String> statuses, bool isPendingAction) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('mentorships')
          .where('mentorId', isEqualTo: mentorId)
          .where('status', whereIn: statuses)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("Aucune donnée à afficher."));
        }

        final requests = snapshot.data!.docs;

        return ListView.builder(
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final doc = requests[index];
            final data = doc.data() as Map<String, dynamic>;
            final studentName = data['studentName'] ?? "Étudiant";
            final status = data['status'];

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(studentName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(isPendingAction ? "Demande en attente" : "Statut : ${status.toUpperCase()}"),
                trailing: isPendingAction 
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check_circle, color: Colors.green),
                          onPressed: () => _updateStatus(context, doc.id, 'accepted', studentName),
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel, color: Colors.redAccent),
                          onPressed: () => _updateStatus(context, doc.id, 'rejected', studentName),
                        ),
                      ],
                    )
                  : Icon(
                      status == 'accepted' ? Icons.verified : Icons.block,
                      color: status == 'accepted' ? Colors.green : Colors.red,
                    ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _updateStatus(BuildContext context, String requestId, String newStatus, String studentName) async {
    try {
      await FirebaseFirestore.instance
          .collection('mentorships')
          .doc(requestId)
          .update({'status': newStatus});

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("$studentName : ${newStatus == 'accepted' ? 'Accepté' : 'Refusé'}"),
            backgroundColor: newStatus == 'accepted' ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur : $e")));
      }
    }
  }
}