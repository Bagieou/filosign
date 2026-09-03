import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 1; // Home selected by default
  // Example streak data: true = active day
  final List<bool> _weekActivity = [true, true, false, true, true, false, false];

  void _onNavTap(int index) {
    setState(() => _selectedIndex = index);
    // TODO: handle navigation for each tab
  }

  @override
  Widget build(BuildContext context) {
    const tealStart = Color(0xFF14B8A6);
    const tealEnd = Color(0xFF0F766E);
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      // Fixed bottom navigation bar
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.arrow_back,
                label: 'Back',
                selected: _selectedIndex == 0,
                onTap: () => _onNavTap(0),
              ),
              _NavItem(
                icon: Icons.home,
                label: 'Home',
                selected: _selectedIndex == 1,
                onTap: () => _onNavTap(1),
              ),
              _NavItem(
                icon: Icons.notifications_none,
                label: 'Alerts',
                selected: _selectedIndex == 2,
                onTap: () => _onNavTap(2),
              ),
              _NavItem(
                icon: Icons.settings,
                label: 'Settings',
                selected: _selectedIndex == 3,
                onTap: () => _onNavTap(3),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Search Bar
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search...',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 2. Streak Bar with week days
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [tealStart, tealEnd],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: tealStart.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.local_fire_department,
                            color: Colors.white, size: 28),
                        SizedBox(width: 10),
                        Text(
                          '7 Day Streak ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Days of week with circles
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(7, (i) {
                        final active = _weekActivity[i];
                        return Column(
                          children: [
                            Text(
                              days[i],
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: active ? Colors.white : Colors.white.withOpacity(0.2),
                                border: Border.all(
                                  color: active ? Colors.transparent : Colors.white.withOpacity(0.4),
                                  width: 2,
                                ),
                              ),
                              child: active
                                  ? const Icon(Icons.check, size: 16, color: tealEnd)
                                  : null,
                            ),
                          ],
                        );
                      }),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 3 & 4. Learn and Practice boxes – each takes half of the remaining space
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: _ActionBox(
                        label: 'Learn',
                        assetIcon: 'assets/icon/learn_icon.png',
                        onTap: () {
                          // TODO: navigate to Learn screen
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _ActionBox(
                        label: 'Practice',
                        assetIcon: 'assets/icon/practice_icon.png',
                        onTap: () {
                          // TODO: navigate to Practice screen
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reusable clickable box for Learn / Practice – expands to fill given constraints
class _ActionBox extends StatelessWidget {
  final String label;
  final String assetIcon;
  final VoidCallback onTap;

  const _ActionBox({
    required this.label,
    required this.assetIcon,
    required this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Icon size based on box height, clamped for readability
        final double iconSize = (constraints.maxHeight * 0.45).clamp(32.0, 80.0);
        final double horizontalPadding = (constraints.maxWidth * 0.04).clamp(12.0, 24.0);
        final double verticalPadding = (constraints.maxHeight * 0.08).clamp(12.0, 32.0);
        final double fontSize = (constraints.maxWidth * 0.045).clamp(14.0, 24.0);
        final double spacing = (constraints.maxWidth * 0.03).clamp(10.0, 20.0);

        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            // height is provided by parent (Expanded)
            padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: horizontalPadding),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  assetIcon,
                  width: iconSize,
                  height: iconSize,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.image_not_supported,
                    size: iconSize,
                    color: Colors.grey,
                  ),
                ),
                SizedBox(width: spacing),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Navigation item used in custom bottom bar
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF0F766E) : Colors.grey;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}