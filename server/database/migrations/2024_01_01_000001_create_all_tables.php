<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration {
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        // Create departments table
        DB::statement("
            CREATE TABLE departments (
                id VARCHAR(191) PRIMARY KEY,
                name VARCHAR(191) NOT NULL UNIQUE,
                createdAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ");

        // Create roles table
        DB::statement("
            CREATE TABLE roles (
                id VARCHAR(191) PRIMARY KEY,
                name VARCHAR(191) NOT NULL UNIQUE,
                createdAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ");

        // Create users table
        DB::statement("
            CREATE TABLE users (
                id VARCHAR(191) PRIMARY KEY,
                employeeCode VARCHAR(191) UNIQUE,
                name VARCHAR(191),
                email VARCHAR(191) UNIQUE,
                contactNumber VARCHAR(191) NOT NULL UNIQUE,
                alternativeNumber VARCHAR(191),
                roleId VARCHAR(191),
                roles JSON,
                departmentId VARCHAR(191),
                otp VARCHAR(191),
                otpExpiry DATETIME,
                lastLogin DATETIME,
                isActive BOOLEAN NOT NULL DEFAULT TRUE,
                createdAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updatedAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                dateOfBirth DATETIME,
                gender VARCHAR(50),
                image TEXT,
                preferredLanguages JSON,
                address TEXT,
                city VARCHAR(191),
                state VARCHAR(191),
                pincode VARCHAR(20),
                country VARCHAR(191),
                district VARCHAR(191),
                area VARCHAR(191),
                latitude DOUBLE,
                longitude DOUBLE,
                aadharCard VARCHAR(191),
                panCard VARCHAR(191),
                password VARCHAR(255),
                notes TEXT,
                workStartTime VARCHAR(8) DEFAULT '09:00:00',
                workEndTime VARCHAR(8) DEFAULT '18:00:00',
                latePunchInGraceMinutes INT DEFAULT 45,
                earlyPunchOutGraceMinutes INT DEFAULT 30,
                FOREIGN KEY (departmentId) REFERENCES departments(id) ON DELETE SET NULL,
                FOREIGN KEY (roleId) REFERENCES roles(id) ON DELETE SET NULL
            )
        ");
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        DB::statement("DROP TABLE IF EXISTS users");
        DB::statement("DROP TABLE IF EXISTS roles");
        DB::statement("DROP TABLE IF EXISTS departments");
    }
};
