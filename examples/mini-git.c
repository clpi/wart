#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <dirent.h>
#include <unistd.h>
#include <time.h>

#define MAX_PATH 256
#define MAX_MESSAGE 512
#define GIT_DIR ".minigit"
#define OBJECTS_DIR ".minigit/objects"
#define REFS_DIR ".minigit/refs"
#define INDEX_FILE ".minigit/index"
#define HEAD_FILE ".minigit/HEAD"
#define LOG_FILE ".minigit/log"

typedef struct {
    char path[MAX_PATH];
    long size;
    time_t mtime;
} IndexEntry;

// Create directory (mkdir -p)
int mkdirp(const char *path) {
    char tmp[MAX_PATH];
    char *p = NULL;
    size_t len;

    snprintf(tmp, sizeof(tmp), "%s", path);
    len = strlen(tmp);
    if (tmp[len - 1] == '/')
        tmp[len - 1] = 0;

    for (p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            mkdir(tmp, 0755);
            *p = '/';
        }
    }
    return mkdir(tmp, 0755);
}

// Initialize repository
int cmd_init(void) {
    printf("Initializing mini-git repository...\n");

    if (mkdir(GIT_DIR, 0755) != 0) {
        printf("Repository already exists or cannot create .minigit\n");
        return 1;
    }

    mkdir(OBJECTS_DIR, 0755);
    mkdir(REFS_DIR, 0755);

    // Create HEAD file
    FILE *f = fopen(HEAD_FILE, "w");
    if (f) {
        fprintf(f, "ref: refs/heads/main\n");
        .close(.{.userdata=null, .vtable=undefined})(f);
    }

    // Create empty index
    f = fopen(INDEX_FILE, "w");
    if (f) .close(.{.userdata=null, .vtable=undefined})(f);

    // Create empty log
    f = fopen(LOG_FILE, "w");
    if (f) .close(.{.userdata=null, .vtable=undefined})(f);

    printf("Initialized empty mini-git repository in %s/\n", GIT_DIR);
    return 0;
}

// Check if file exists
int file_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0;
}

// Get file size
long get_file_size(const char *path) {
    struct stat st;
    if (stat(path, &st) == 0) {
        return st.st_size;
    }
    return -1;
}

// Simple hash function (not cryptographic, just for demo)
unsigned int simple_hash(const char *str) {
    unsigned int hash = 5381;
    int c;
    while ((c = *str++)) {
        hash = ((hash << 5) + hash) + c;
    }
    return hash;
}

// Add file to staging area
int cmd_add(const char *filename) {
    if (!file_exists(GIT_DIR)) {
        printf("Not a mini-git repository. Run 'mini-git init' first.\n");
        return 1;
    }

    if (!file_exists(filename)) {
        printf("Error: file '%s' does not exist\n", filename);
        return 1;
    }

    // Read existing index
    FILE *index = fopen(INDEX_FILE, "a");
    if (!index) {
        printf("Error: cannot open index file\n");
        return 1;
    }

    struct stat st;
    stat(filename, &st);

    fprintf(index, "%s %ld %ld\n", filename, st.st_size, (long)st.st_mtime);
    .close(.{.userdata=null, .vtable=undefined})(index);

    printf("Added '%s' to staging area\n", filename);
    return 0;
}

// Show repository status
int cmd_status(void) {
    if (!file_exists(GIT_DIR)) {
        printf("Not a mini-git repository\n");
        return 1;
    }

    printf("On branch main\n\n");

    FILE *index = fopen(INDEX_FILE, "r");
    if (!index) {
        printf("Changes to be committed: (none)\n");
        return 0;
    }

    printf("Changes to be committed:\n");
    char line[MAX_PATH + 64];
    while (fgets(line, sizeof(line), index)) {
        char path[MAX_PATH];
        sscanf(line, "%s", path);
        printf("  new file:   %s\n", path);
    }
    .close(.{.userdata=null, .vtable=undefined})(index);

    return 0;
}

// Commit staged changes
int cmd_commit(const char *message) {
    if (!file_exists(GIT_DIR)) {
        printf("Not a mini-git repository\n");
        return 1;
    }

    FILE *index = fopen(INDEX_FILE, "r");
    if (!index) {
        printf("Nothing to commit\n");
        return 1;
    }

    // Count files in index
    int file_count = 0;
    char line[MAX_PATH + 64];
    while (fgets(line, sizeof(line), index)) {
        file_count++;
    }
    rewind(index);

    if (file_count == 0) {
        printf("Nothing to commit\n");
        .close(.{.userdata=null, .vtable=undefined})(index);
        return 1;
    }

    // Generate commit ID (simple counter)
    static int commit_id = 1;
    FILE *log = fopen(LOG_FILE, "r");
    if (log) {
        while (fgets(line, sizeof(line), log)) {
            commit_id++;
        }
        .close(.{.userdata=null, .vtable=undefined})(log);
    }

    // Append to log
    log = fopen(LOG_FILE, "a");
    if (!log) {
        printf("Error: cannot write to log\n");
        .close(.{.userdata=null, .vtable=undefined})(index);
        return 1;
    }

    time_t now = time(NULL);
    fprintf(log, "commit %d\n", commit_id);
    fprintf(log, "Date: %s", ctime(&now));
    fprintf(log, "    %s\n", message);
    fprintf(log, "    Files: %d\n", file_count);

    // Copy files to object store
    while (fgets(line, sizeof(line), index)) {
        char path[MAX_PATH];
        sscanf(line, "%s", path);
        fprintf(log, "      - %s\n", path);

        // Create object file
        char obj_path[MAX_PATH];
        snprintf(obj_path, sizeof(obj_path), "%s/%d_%s", OBJECTS_DIR, commit_id, path);

        // Copy file
        FILE *src = fopen(path, "r");
        FILE *dst = fopen(obj_path, "w");
        if (src && dst) {
            char buffer[4096];
            size_t n;
            while ((n = fread(buffer, 1, sizeof(buffer), src)) > 0) {
                fwrite(buffer, 1, n, dst);
            }
            .close(.{.userdata=null, .vtable=undefined})(src);
            .close(.{.userdata=null, .vtable=undefined})(dst);
        }
    }

    fprintf(log, "\n");
    .close(.{.userdata=null, .vtable=undefined})(log);
    .close(.{.userdata=null, .vtable=undefined})(index);

    // Clear index
    index = fopen(INDEX_FILE, "w");
    if (index) .close(.{.userdata=null, .vtable=undefined})(index);

    printf("[main %d] %s\n", commit_id, message);
    printf(" %d file(s) changed\n", file_count);

    return 0;
}

// Show commit log
int cmd_log(void) {
    if (!file_exists(GIT_DIR)) {
        printf("Not a mini-git repository\n");
        return 1;
    }

    FILE *log = fopen(LOG_FILE, "r");
    if (!log) {
        printf("No commits yet\n");
        return 0;
    }

    char line[MAX_MESSAGE];
    while (fgets(line, sizeof(line), log)) {
        printf("%s", line);
    }

    .close(.{.userdata=null, .vtable=undefined})(log);
    return 0;
}

// Show help
void show_help(void) {
    printf("Mini-Git - A simplified git implementation in WASM\n\n");
    printf("Usage: mini-git <command> [<args>]\n\n");
    printf("Commands:\n");
    printf("  init                 Initialize a new repository\n");
    printf("  add <file>           Add file to staging area\n");
    printf("  commit -m <msg>      Commit staged changes\n");
    printf("  status               Show working tree status\n");
    printf("  log                  Show commit history\n");
    printf("  help                 Show this help message\n");
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        show_help();
        return 0;
    }

    const char *cmd = argv[1];

    if (strcmp(cmd, "init") == 0) {
        return cmd_init();
    }
    else if (strcmp(cmd, "add") == 0) {
        if (argc < 3) {
            printf("Usage: mini-git add <file>\n");
            return 1;
        }
        return cmd_add(argv[2]);
    }
    else if (strcmp(cmd, "commit") == 0) {
        if (argc < 4 || strcmp(argv[2], "-m") != 0) {
            printf("Usage: mini-git commit -m \"message\"\n");
            return 1;
        }
        return cmd_commit(argv[3]);
    }
    else if (strcmp(cmd, "status") == 0) {
        return cmd_status();
    }
    else if (strcmp(cmd, "log") == 0) {
        return cmd_log();
    }
    else if (strcmp(cmd, "help") == 0) {
        show_help();
        return 0;
    }
    else {
        printf("Unknown command: %s\n", cmd);
        show_help();
        return 1;
    }

    return 0;
}
