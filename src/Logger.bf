namespace Treasure;
using System;

enum LogLevel
{
    DEBUG,
    INFO,
    WARN,
    ERROR
}

class Logger
{
    public static void Log(StringView message, StringView arg1, LogLevel level)
    {
        // Placeholder for logging implementation
        Console.WriteLine(message, arg1);
    }

    public static void Log(StringView message, StringView arg1, StringView arg2, LogLevel level)
    {
        // Placeholder for logging implementation
        Console.WriteLine(message, arg1, arg2);
    }
}