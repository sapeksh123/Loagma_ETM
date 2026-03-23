import 'dart:async';
import 'dart:convert';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';

import '../services/api_config.dart';
import '../services/chat_service.dart';

class ChatRealtimeEvent {
  final String channelName;
  final String eventName;
  final Map<String, dynamic> data;

  const ChatRealtimeEvent({
    required this.channelName,
    required this.eventName,
    required this.data,
  });
}

class ChatRealtimeClient {
  ChatRealtimeClient._();

  static final ChatRealtimeClient instance = ChatRealtimeClient._();

  final _events = StreamController<ChatRealtimeEvent>.broadcast();
  final _connectionStates = StreamController<String>.broadcast();
  final _subscribedChannels = <String>{};
  final PusherChannelsFlutter _pusher = PusherChannelsFlutter.getInstance();

  String? _userId;
  String? _userRole;
  bool _initialized = false;

  Stream<ChatRealtimeEvent> get events => _events.stream;
  Stream<String> get connectionStates => _connectionStates.stream;

  Future<void> connect({
    required String userId,
    required String userRole,
  }) async {
    _userId = userId;
    _userRole = userRole;

    if (!_initialized) {
      await _pusher.init(
        apiKey: ApiConfig.reverbAppKey,
        cluster: '',
        host: ApiConfig.reverbHost,
        wsPort: ApiConfig.reverbPort,
        wssPort: ApiConfig.reverbPort,
        useTLS: ApiConfig.reverbUseTls,
        onAuthorizer: (
          String channelName,
          String socketId,
          dynamic _,
        ) async {
          final currentUserId = _userId;
          final currentUserRole = _userRole;
          if (currentUserId == null || currentUserRole == null) {
            throw StateError('Realtime client is missing actor credentials');
          }

          return ChatService.authorizeRealtime(
            userId: currentUserId,
            userRole: currentUserRole,
            socketId: socketId,
            channelName: channelName,
          );
        },
        onConnectionStateChange: (dynamic currentState, dynamic previousState) {
          _connectionStates.add(currentState.toString());
        },
        onError: (String message, int? code, dynamic exception) {
          _connectionStates.add('error:$message');
        },
        onEvent: (PusherEvent event) {
          final rawData = event.data;
          dynamic parsed = <String, dynamic>{};
          if (rawData is String && rawData.isNotEmpty) {
            try {
              parsed = jsonDecode(rawData);
            } catch (_) {
              parsed = <String, dynamic>{'raw': rawData};
            }
          } else if (rawData is Map<String, dynamic>) {
            parsed = rawData;
          }
          _events.add(
            ChatRealtimeEvent(
              channelName: event.channelName,
              eventName: event.eventName,
              data: parsed is Map<String, dynamic>
                  ? parsed
                  : <String, dynamic>{'data': parsed},
            ),
          );
        },
      );
      _initialized = true;
    }

    await _pusher.connect();
  }

  Future<void> subscribeUserChannel(String userId) async {
    await _subscribe('private-chat.user.$userId');
  }

  Future<void> subscribeThreadChannel(String threadId) async {
    await _subscribe('private-chat.thread.$threadId');
  }

  Future<void> unsubscribeThreadChannel(String threadId) async {
    final channelName = 'private-chat.thread.$threadId';
    if (_subscribedChannels.remove(channelName)) {
      await _pusher.unsubscribe(channelName: channelName);
    }
  }

  Future<void> disconnect() async {
    _subscribedChannels.clear();
    await _pusher.disconnect();
  }

  Future<void> _subscribe(String channelName) async {
    if (_subscribedChannels.contains(channelName)) return;
    if (_userId == null || _userRole == null) {
      throw StateError('Realtime client is not connected');
    }
    await _pusher.subscribe(channelName: channelName);
    _subscribedChannels.add(channelName);
  }
}
