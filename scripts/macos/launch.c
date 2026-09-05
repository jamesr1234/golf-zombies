#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/utsname.h>
#include <time.h>
#include <unistd.h>

#define WORKSPACE_LOG "/Users/jamesritchie/golf-zombies/.cursor/debug-ef8322.log"

static void agent_log(const char *dir, const char *arch, int compat) {
	char nearby[1024];
	snprintf(nearby, sizeof(nearby), "%s/debug-ef8322.log", dir);
	long long stamp = (long long)time(NULL) * 1000LL;
	char line[512];
	snprintf(line, sizeof(line),
			"{\"sessionId\":\"ef8322\",\"hypothesisId\":\"F\",\"location\":\"macos/launch.c\","
			"\"message\":\"pre-engine launch\",\"timestamp\":%lld,"
			"\"data\":{\"arch\":\"%s\",\"compat\":%s,\"stub\":\"macho\"}}\n",
			stamp, arch, compat ? "true" : "false");
	const char *paths[] = {WORKSPACE_LOG, nearby, NULL};
	for (int i = 0; paths[i]; i++) {
		FILE *f = fopen(paths[i], "a");
		if (f) {
			fputs(line, f);
			fclose(f);
		}
	}
}

int main(int argc, char **argv) {
	char dir[1024];
	strncpy(dir, argv[0], sizeof(dir) - 1);
	char *slash = strrchr(dir, '/');
	if (slash) {
		*slash = '\0';
	} else {
		strncpy(dir, ".", sizeof(dir) - 1);
	}

	char bin[1024];
	snprintf(bin, sizeof(bin), "%s/golf zombies.bin", dir);

	struct utsname u;
	uname(&u);
	int compat = strcmp(u.machine, "x86_64") == 0;
	agent_log(dir, u.machine, compat);

	char **nargv = calloc((size_t)argc + 3, sizeof(char *));
	if (!nargv) {
		return 1;
	}
	int i = 0;
	nargv[i++] = bin;
	if (compat) {
		nargv[i++] = "--rendering-method";
		nargv[i++] = "gl_compatibility";
	}
	for (int a = 1; a < argc; a++) {
		nargv[i++] = argv[a];
	}
	execv(bin, nargv);
	perror("golf zombies.bin");
	return 127;
}
