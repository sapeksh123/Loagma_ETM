<?php

namespace App\Events;

use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class ChatThreadEvent implements ShouldBroadcastNow
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    /**
     * @param  string[]  $channels
     * @param  array<string, mixed>  $payload
     */
    public function __construct(
        public array $channels,
        public string $eventName,
        public array $payload = []
    ) {
    }

    public function broadcastAs(): string
    {
        return $this->eventName;
    }

    public function broadcastOn(): array
    {
        return array_map(
            static fn (string $channel) => new PrivateChannel($channel),
            $this->channels
        );
    }

    public function broadcastWith(): array
    {
        return $this->payload;
    }
}
