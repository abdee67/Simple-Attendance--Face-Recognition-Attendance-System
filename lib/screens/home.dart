import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget{
  final String username;
  const HomeScreen({required this.username,super.key});


    @override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
     actions: [
        IconButton(
          icon: Icon(Icons.logout),
          onPressed: () => Navigator.pushNamed(context, '/login'),
        ),
      ],
      title: Text(
        'Home Dashboard',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      centerTitle: true,
      backgroundColor: Colors.orangeAccent,
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
    ),
    body: Padding(
      padding: const EdgeInsets.all(20.0),
      child: GridView.count(
        crossAxisCount: 3,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
        children: [
          _buildDashboardButton(
            icon: Icons.assignment_ind,
            label: "Site Entry",
            color: const Color(0xFF4CAF50),
            onPressed: () => Navigator.pushNamed(context, '/sites'),
          ),
        ],
      ),
    ),
  );
}

// Reusable button widget for cleaner code
Widget _buildDashboardButton({
  required IconData icon,
  required String label,
  required Color color,
  required VoidCallback onPressed,
}) {
  return Card(
    elevation: 5,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onPressed,
      splashColor: color.withOpacity(0.2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: color),
          SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    ),
  );
}

}