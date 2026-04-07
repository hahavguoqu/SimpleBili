import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/auth_provider.dart';
import '../features/auth/login_page.dart';
import '../features/feed/feed_page.dart';
import '../features/search/search_page.dart';
import '../features/player/player_page.dart';
import '../features/up/up_space_page.dart';
import '../features/favorite/favorite_page.dart';

class RouterRefreshNotifier extends ChangeNotifier {
  late final StreamSubscription<dynamic> _sub;

  RouterRefreshNotifier(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = ref.read(authProvider.notifier);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: RouterRefreshNotifier(authNotifier.stream),
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(path: '/', builder: (context, state) => const FeedPage()),
      GoRoute(path: '/search', builder: (context, state) => const SearchPage()),
      GoRoute(
        path: '/up/:mid',
        builder: (context, state) {
          final mid = state.pathParameters['mid']!;
          return UpSpacePage(mid: mid);
        },
      ),
      GoRoute(
        path: '/player/:bvid',
        builder: (context, state) {
          final bvid = state.pathParameters['bvid']!;
          return PlayerPage(bvid: bvid);
        },
      ),
      GoRoute(
        path: '/favorite',
        builder: (context, state) => const FavoritePage(),
      ),
      GoRoute(
        path: '/favorite/:mediaId',
        builder: (context, state) {
          final mediaId = int.parse(state.pathParameters['mediaId']!);
          return FavoriteDetailPage(mediaId: mediaId);
        },
      ),
    ],
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final isAuth = authState.status == AuthStatus.authenticated;
      final isGoingToLogin = state.uri.path == '/login';

      if (!isAuth && !isGoingToLogin) {
        return '/login';
      }
      if (isAuth && isGoingToLogin) {
        return '/';
      }
      return null;
    },
  );
});
