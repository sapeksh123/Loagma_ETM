<?php

use Illuminate\Support\Facades\Broadcast;
use Illuminate\Support\Facades\DB;

Broadcast::channel('chat.thread.{threadId}', function ($user, string $threadId) {
    return DB::table('chat_participants')
        ->where('thread_id', $threadId)
        ->where('user_id', $user->id)
        ->exists();
});

Broadcast::channel('presence.user.{userId}', function ($user, string $userId) {
    return (string) $user->id === $userId;
});
