#include <iostream>
#include <unistd.h>
#include <spawn.h>

extern char **environ;

int main(int argc, char **argv)
{
    int start_pid = getpid();
    std::cout << "PID=" << start_pid << " main\n";
    posix_spawnattr_t attr;
    posix_spawn_file_actions_t file_actions;
    int fork_pid;
    posix_spawnattr_init(&attr);
    posix_spawn_file_actions_init(&file_actions);
    posix_spawn(&fork_pid, "/usr/bin/cat", &file_actions, &attr, argv, environ);
    std::cout << "PID=" << fork_pid << " forked\n";
    return 0;
}
