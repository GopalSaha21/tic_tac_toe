import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  // Flutter framework ke ensure korbe je widgets tree ready - async operation er jonno required
  WidgetsFlutterBinding.ensureInitialized();
  
  // Firebase initialize korchi - app er backend connection setup
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSyAmdzfG8IEmu-fpYyFI7X0LrjihkgvCBXY',
      appId: '1:976188271127:android:ed65b2c4c06dde55330a52',
      messagingSenderId: '976188271127',
      projectId: 'tic-tac-toe-6b321',
    ),
  );
  
  runApp(const TicTacToeApp());
}

class TicTacToeApp extends StatelessWidget {
  const TicTacToeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Game logic er state manage korbe - ChangeNotifierProvider use kore UI auto rebuild hobe
        ChangeNotifierProvider(create: (_) => GameProvider()),
        // Firebase service - dependency injection er moto, anywhere use kora jabe
        Provider(create: (_) => FirestoreService()),
      ],
      child: MaterialApp(
        title: 'Tic Tac Toe',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          primarySwatch: Colors.blue,
          useMaterial3: true, // latest Material design
          scaffoldBackgroundColor: const Color(0xFF0F172A), // slate dark color
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            titleTextStyle: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

// ============================================================
// Firebase Service - all database operations
// ============================================================
class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String collectionName = 'matches';

  // Save match to Firebase
  Future<void> saveMatch(MatchModel match) async {
    try {
      await _firestore.collection(collectionName).add({
        'playerX': match.playerX,
        'playerO': match.playerO,
        'winner': match.winner,
        'board': match.board,
        'createdAt': FieldValue.serverTimestamp(), // Firebase server time
        'result': match.result,
      });
      print('✅ Match saved to Firebase!');
    } catch (e) {
      print('❌ Error saving to Firebase: $e');
      rethrow; // Error re-throw korlam jate caller handle korte pare
    }
  }

  // Get all matches - real-time stream
  Stream<List<MatchModel>> getAllMatches() {
    return _firestore
        .collection(collectionName)
        .orderBy('createdAt', descending: true) // latest first
        .snapshots() // real-time listener
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return MatchModel.fromFirestore(doc);
      }).toList();
    });
  }

  // Get limited number of recent matches for performance
  Stream<List<MatchModel>> getRecentMatches({int limit = 50}) {
    return _firestore
        .collection(collectionName)
        .orderBy('createdAt', descending: true)
        .limit(limit) // only fetch 50 records
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return MatchModel.fromFirestore(doc);
      }).toList();
    });
  }

  // Delete single match by ID
  Future<void> deleteMatch(String matchId) async {
    try {
      await _firestore.collection(collectionName).doc(matchId).delete();
      print('✅ Match deleted successfully!');
    } catch (e) {
      print('❌ Error deleting match: $e');
      rethrow;
    }
  }

  // Delete all matches using batch operation
  Future<void> deleteAllMatches() async {
    try {
      final matches = await _firestore.collection(collectionName).get();
      final batch = _firestore.batch(); // multiple operations in single network call
      
      for (var doc in matches.docs) {
        batch.delete(doc.reference);
      }
      
      await batch.commit();
      print('✅ All matches deleted!');
    } catch (e) {
      print('❌ Error deleting all matches: $e');
      rethrow;
    }
  }
}

// ============================================================
// Data Models
// ============================================================
class MatchModel {
  final String? id;
  final String playerX;
  final String playerO;
  final String winner; // 'X', 'O', or 'Tie'
  final List<String> board;
  final DateTime createdAt;
  final String result;

  MatchModel({
    this.id,
    required this.playerX,
    required this.playerO,
    required this.winner,
    required this.board,
    required this.createdAt,
    required this.result,
  });

  // Convert Firestore document to MatchModel
  factory MatchModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MatchModel(
      id: doc.id,
      playerX: data['playerX'] ?? 'Player X',
      playerO: data['playerO'] ?? 'Player O',
      winner: data['winner'] ?? 'Tie',
      board: List<String>.from(data['board'] ?? []),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      result: data['result'] ?? '',
    );
  }

  // Convert MatchModel to Map for Firebase
  Map<String, dynamic> toMap() {
    return {
      'playerX': playerX,
      'playerO': playerO,
      'winner': winner,
      'board': board,
      'createdAt': FieldValue.serverTimestamp(),
      'result': result,
    };
  }
}

// Local match result model
class MatchResult {
  final String playerX;
  final String playerO;
  final String result;
  final DateTime timestamp;

  MatchResult({
    required this.playerX,
    required this.playerO,
    required this.result,
    required this.timestamp,
  });
}

// ============================================================
// Game Provider (State Management)
// ============================================================
class GameProvider extends ChangeNotifier {
  List<String> _board = List.filled(9, ''); // 9 cells, empty string means empty
  String _currentPlayer = 'X'; // X always starts
  bool _gameActive = true;

  String _playerXName = 'Player X';
  String _playerOName = 'Player O';

  int _xWins = 0;
  int _oWins = 0;
  int _draws = 0;

  List<MatchResult> _history = [];
  bool _isSaving = false;

  // Getters - private fields access korar jonno
  List<String> get board => _board;
  String get currentPlayer => _currentPlayer;
  bool get gameActive => _gameActive;
  String get playerXName => _playerXName;
  String get playerOName => _playerOName;
  int get xWins => _xWins;
  int get oWins => _oWins;
  int get draws => _draws;
  List<MatchResult> get history => _history;
  bool get isSaving => _isSaving;

  // All winning combinations in Tic Tac Toe
  static const List<List<int>> winPatterns = [
    [0, 1, 2], [3, 4, 5], [6, 7, 8], // rows
    [0, 3, 6], [1, 4, 7], [2, 5, 8], // columns
    [0, 4, 8], [2, 4, 6], // diagonals
  ];

  // Check if any player has won
  String? checkWinner() {
    for (var pattern in winPatterns) {
      if (pattern.every((i) => _board[i] == 'X')) return 'X';
      if (pattern.every((i) => _board[i] == 'O')) return 'O';
    }
    return null;
  }

  // Check if game is a draw (board full but no winner)
  bool isDraw() {
    return _board.every((cell) => cell.isNotEmpty) && checkWinner() == null;
  }

  // Main game logic - called when player taps a cell
  void makeMove(int index) {
    // Validation: if game inactive, cell filled, or saving then ignore
    if (!_gameActive || _board[index].isNotEmpty || _isSaving) return;

    _board[index] = _currentPlayer;
    notifyListeners(); // Trigger UI rebuild

    final winner = checkWinner();
    if (winner != null) {
      _gameActive = false;
      String resultText;
      if (winner == 'X') {
        _xWins++;
        resultText = '$_playerXName wins!';
      } else {
        _oWins++;
        resultText = '$_playerOName wins!';
      }
      _saveMatchResult(resultText, winner);
      notifyListeners();
      return;
    }

    if (isDraw()) {
      _gameActive = false;
      _draws++;
      _saveMatchResult('Draw', 'Tie');
      notifyListeners();
      return;
    }

    // Switch player for next turn
    _currentPlayer = (_currentPlayer == 'X') ? 'O' : 'X';
    notifyListeners();
  }

  // Save match result to local history and Firebase
  Future<void> _saveMatchResult(String resultText, String winner) async {
    // Save locally first for instant feedback
    final match = MatchResult(
      playerX: _playerXName,
      playerO: _playerOName,
      result: resultText,
      timestamp: DateTime.now(),
    );
    _history.insert(0, match);
    if (_history.length > 20) _history.removeLast(); // Keep only recent 20

    // Save to Firebase
    try {
      final firestoreService = FirestoreService();
      final firestoreMatch = MatchModel(
        playerX: _playerXName,
        playerO: _playerOName,
        winner: winner,
        board: List.from(_board),
        createdAt: DateTime.now(),
        result: resultText,
      );
      
      _isSaving = true;
      notifyListeners(); // Show loading indicator
      
      await firestoreService.saveMatch(firestoreMatch);
    } catch (e) {
      print('Error saving to Firebase: $e');
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  // Reset only the board (keep scores)
  void resetBoard() {
    _board = List.filled(9, '');
    _gameActive = true;
    _currentPlayer = 'X';
    notifyListeners();
  }

  // Update player names from text fields
  void updatePlayerNames({required String xName, required String oName}) {
    _playerXName = xName.trim().isEmpty ? 'Player X' : xName.trim();
    _playerOName = oName.trim().isEmpty ? 'Player O' : oName.trim();
    notifyListeners();
  }

  // Reset everything - scores, history, board
  void resetScoresAndHistory() {
    _xWins = 0;
    _oWins = 0;
    _draws = 0;
    _history.clear();
    resetBoard();
    notifyListeners();
  }

  // Show winner dialog when game ends
  void showWinnerDialog(BuildContext context) {
    if (!_gameActive && !_isSaving) {
      String winnerMessage = '';
      final winner = checkWinner();
      if (winner == 'X') {
        winnerMessage = '$_playerXName wins! 🎉';
      } else if (winner == 'O') {
        winnerMessage = '$_playerOName wins! 🎉';
      } else if (isDraw()) {
        winnerMessage = 'Game is a draw! 🤝';
      }
      if (winnerMessage.isNotEmpty) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text(winnerMessage),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  resetBoard();
                },
                child: const Text('Play Again'),
              ),
            ],
          ),
        );
      }
    }
  }
}

// ============================================================
// Splash Screen - App start animation
// ============================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin { // AnimationController er jonno vsync needed
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    // Animation controller - duration 2 seconds
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    // Fade animation from 0 to 1
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    // Scale animation for zoom effect
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward(); // Start animation

    // Navigate to home after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) { // Check if widget still in tree
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const GameHomeScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose(); // Cleanup animation controller
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Animated logo container
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.cyanAccent, Colors.pinkAccent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.cyanAccent.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          "✕ ●",
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    const Text(
                      "Tic Tac Toe",
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 60),
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================
// Game Home Screen - Main UI
// ============================================================
class GameHomeScreen extends StatefulWidget {
  const GameHomeScreen({super.key});

  @override
  State<GameHomeScreen> createState() => _GameHomeScreenState();
}

class _GameHomeScreenState extends State<GameHomeScreen> {
  // Bottom navigation selected index tracking
  int _selectedNavIndex = 0;

  // Dialog for editing player names
  void _showEditNamesDialog(GameProvider provider) {
    final xController = TextEditingController(text: provider.playerXName);
    final oController = TextEditingController(text: provider.playerOName);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Change Player Names'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: xController,
              decoration: const InputDecoration(
                labelText: 'Player X Name',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: oController,
              decoration: const InputDecoration(
                labelText: 'Player O Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              provider.updatePlayerNames(
                xName: xController.text,
                oName: oController.text,
              );
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<GameProvider>(context);

    // Show winner dialog when game ends
    if (!provider.gameActive && provider.history.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        provider.showWinnerDialog(context);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tic Tac Toe'),
        actions: [
          // Only edit names button - history button removed from appbar
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Change Names',
            onPressed: () => _showEditNamesDialog(provider),
          ),
        ],
      ),
      body: Column(
        children: [
          // Score card - shows current scores
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ScoreTile(
                  name: provider.playerXName,
                  symbol: '✕',
                  wins: provider.xWins,
                  color: Colors.cyanAccent,
                ),
                Container(width: 1, height: 40, color: Colors.white24),
                _ScoreTile(
                  name: provider.playerOName,
                  symbol: '●',
                  wins: provider.oWins,
                  color: Colors.pinkAccent,
                ),
                Container(width: 1, height: 40, color: Colors.white24),
                _ScoreTile(
                  name: 'Draws',
                  symbol: '⚖️',
                  wins: provider.draws,
                  color: Colors.white70,
                ),
              ],
            ),
          ),
          
          // Current player turn indicator
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(
                color: provider.currentPlayer == 'X'
                    ? Colors.cyanAccent.withOpacity(0.5)
                    : Colors.pinkAccent.withOpacity(0.5),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  provider.currentPlayer == 'X' ? '✕' : '●',
                  style: TextStyle(
                    fontSize: 28,
                    color: provider.currentPlayer == 'X'
                        ? Colors.cyanAccent
                        : Colors.pinkAccent,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  provider.gameActive
                      ? '${provider.currentPlayer == 'X' ? provider.playerXName : provider.playerOName}\'s turn'
                      : 'Game Over',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          
          // Loading indicator while saving to Firebase
          if (provider.isSaving)
            const LinearProgressIndicator(),
          
          // Game board grid
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width - 32,
                  maxHeight: MediaQuery.of(context).size.width - 32,
                ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 9,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemBuilder: (_, i) => GameCell(index: i),
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          // Bottom Navigation Bar - 3 buttons (Board, Reset, History)
          _buildModernBottomNav(provider),
        ],
      ),
    );
  }

  // Modern bottom navigation with 3 buttons
  Widget _buildModernBottomNav(GameProvider provider) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2538), Color(0xFF111B28)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, -2),
          ),
        ],
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Board button - returns to game board
          _NavItem(
            icon: Icons.grid_3x3,
            label: 'Board',
            index: 0,
            selectedIndex: _selectedNavIndex,
            onTap: () => setState(() => _selectedNavIndex = 0),
          ),
          
          // Reset button - resets current game
          _NavItem(
            icon: Icons.refresh,
            label: 'Reset',
            index: 1,
            selectedIndex: _selectedNavIndex,
            onTap: () {
              setState(() => _selectedNavIndex = 1);
              provider.resetBoard();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Game reset'),
                  duration: Duration(milliseconds: 800),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: Colors.cyanAccent,
                  shape: StadiumBorder(),
                ),
              );
              // Reset selection after animation
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) setState(() => _selectedNavIndex = 0);
              });
            },
          ),
          
          // History button - navigates to match history screen
          _NavItem(
            icon: Icons.history,
            label: 'History',
            index: 2,
            selectedIndex: _selectedNavIndex,
            onTap: () {
              setState(() => _selectedNavIndex = 2);
              // Navigate to history screen
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              ).then((_) {
                // Reset selection when returning from history
                if (mounted) setState(() => _selectedNavIndex = 0);
              });
            },
          ),
        ],
      ),
    );
  }
}

// Individual game cell widget
class GameCell extends StatelessWidget {
  final int index;
  const GameCell({super.key, required this.index});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<GameProvider>(context);
    final value = provider.board[index];
    final isX = value == 'X';
    final isO = value == 'O';

    return GestureDetector(
      onTap: () => provider.makeMove(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              value == 'X' ? '✕' : (value == 'O' ? '●' : ''),
              key: ValueKey(value), // For animation
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: isX
                    ? Colors.cyanAccent
                    : isO
                        ? Colors.pinkAccent
                        : Colors.transparent, // Empty cells are invisible
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Score tile for scoreboard display
class _ScoreTile extends StatelessWidget {
  final String name;
  final String symbol;
  final int wins;
  final Color color;
  const _ScoreTile({
    required this.name,
    required this.symbol,
    required this.wins,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(symbol, style: TextStyle(color: color, fontSize: 24)),
        const SizedBox(height: 4),
        Text(
          name,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          '$wins',
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

// Bottom navigation item - animated on selection
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int selectedIndex;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedIndex == index;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 20 : 12,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Colors.cyanAccent, Colors.blueAccent],
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(40),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.cyanAccent.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.black87 : Colors.white70,
              size: 22,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================
// History Screen - Shows all matches from Firebase
// ============================================================
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  // Delete single match with confirmation
  Future<void> _deleteMatch(BuildContext context, String matchId, String matchResult) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Match'),
        content: Text('Are you sure you want to delete this match?\n\n$matchResult'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      try {
        final firestoreService = Provider.of<FirestoreService>(context, listen: false);
        await firestoreService.deleteMatch(matchId);
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Match deleted successfully'),
              duration: Duration(seconds: 1),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting match: $e'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Match History'),
        actions: [
          // Delete all matches button
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear All History',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Clear All History?'),
                  content: const Text('All match records will be deleted permanently.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await firestoreService.deleteAllMatches();
                        if (context.mounted) Navigator.pop(context);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('All history cleared'),
                              duration: Duration(seconds: 1),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      },
                      child: const Text(
                        'Delete All',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<MatchModel>>(
        stream: firestoreService.getRecentMatches(limit: 50),
        builder: (context, snapshot) {
          // Handle error state
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {},
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            );
          }

          // Show loading indicator
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final matches = snapshot.data ?? [];

          // Show empty state
          if (matches.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.white54),
                  SizedBox(height: 16),
                  Text(
                    'No matches played yet\nStart a game',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            );
          }

          // Display list of matches
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: matches.length,
            itemBuilder: (context, index) {
              final match = matches[index];
              final formattedDate = DateFormat('dd MMM yyyy, hh:mm a')
                  .format(match.createdAt);
              
              // Set color and icon based on winner
              Color resultColor;
              IconData resultIcon;
              if (match.winner == 'X') {
                resultColor = Colors.cyanAccent;
                resultIcon = Icons.emoji_events;
              } else if (match.winner == 'O') {
                resultColor = Colors.pinkAccent;
                resultIcon = Icons.emoji_events;
              } else {
                resultColor = Colors.white70;
                resultIcon = Icons.handshake;
              }
              
              // Dismissible allows swipe-to-delete
              return Dismissible(
                key: Key(match.id ?? DateTime.now().toString()),
                direction: DismissDirection.endToStart,
                onDismissed: (direction) async {
                  if (match.id != null) {
                    await firestoreService.deleteMatch(match.id!);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${match.result} deleted'),
                          duration: const Duration(seconds: 1),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  }
                },
                background: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(
                    Icons.delete,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                child: Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ListTile(
                    leading: Icon(resultIcon, color: resultColor),
                    title: Text(
                      match.result,
                      style: TextStyle(
                        color: resultColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '${match.playerX} ✕ vs ● ${match.playerO}\n$formattedDate',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: resultColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            match.winner == 'Tie' ? 'Draw' : '${match.winner} wins',
                            style: TextStyle(
                              color: resultColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                          onPressed: () => _deleteMatch(context, match.id!, match.result),
                          tooltip: 'Delete this match',
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}