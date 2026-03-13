<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Notification extends Model
{
    use HasFactory;

    /**
     * The attributes that are mass assignable.
     *
     * @var list<string>
     */
    protected $fillable = [
        'employee_id',
        'task_id',
        'subtask_index',
        'type',
        'title',
        'message',
        'is_read',
    ];

    /**
     * Indicates if the model should be timestamped.
     */
    public $timestamps = false;
}

