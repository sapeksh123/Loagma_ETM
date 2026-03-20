<?php

namespace App\Events;

use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcast;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class ChatThreadEvent implements ShouldBroadcast, ShouldQueue
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public function __construct(
        public string $threadId,
        public string $eventType,
        public array $payload = []
    ) {
    }

    public function broadcastAs(): string
    {
        return 'chat.thread.event';
    }

    public function broadcastOn(): array
    {
        return [new PrivateChannel('chat.thread.' . $this->threadId)];
    }

    public function broadcastWith(): array
    {
        return [
            'thread_id' => $this->threadId,
            'event_type' => $this->eventType,
            'payload' => $this->payload,
        ];
    }
}
