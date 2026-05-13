#include <array>
#include <cstdint>
#include <cstdio>
#include <cstring>

namespace {

constexpr uint32_t kBlobCount = 192;
constexpr uint32_t kBlobBytes = 512;
constexpr uint32_t kCommitCount = 96;
constexpr uint32_t kArenaBytes = 512 * 1024;
constexpr uint32_t kBuckets = 1024;

struct Blob {
  char path[40];
  uint32_t len;
  std::array<uint8_t, kBlobBytes> data;
  uint64_t hash;
  uint32_t flags;
};

struct Commit {
  uint64_t id;
  uint64_t parent;
  uint64_t tree;
  uint64_t diff;
  uint32_t touched;
};

struct Repository {
  std::array<Blob, kBlobCount> blobs;
  std::array<Commit, kCommitCount> commits;
  std::array<uint8_t, kArenaBytes> arena;
  std::array<uint64_t, kBuckets> index_buckets;
};

static uint64_t g_seed = 0x9d39247e33776d41ULL;

static inline uint64_t next_u64() {
  g_seed = g_seed * 6364136223846793005ULL + 1442695040888963407ULL;
  return g_seed;
}

static inline uint64_t mix64(uint64_t v) {
  v ^= v >> 33;
  v *= 0xff51afd7ed558ccdULL;
  v ^= v >> 33;
  v *= 0xc4ceb9fe1a85ec53ULL;
  v ^= v >> 33;
  return v;
}

static uint64_t hash_bytes(const uint8_t *data, uint32_t len) {
  uint64_t h = 1469598103934665603ULL;
  for (uint32_t i = 0; i < len; ++i) {
    h ^= static_cast<uint64_t>(data[i]);
    h *= 1099511628211ULL;
    h = (h << 5) | (h >> 59);
  }
  return mix64(h ^ len);
}

static void fill_path(char *out, uint32_t id) {
  static constexpr char kPrefix[] = "repo/src/";
  std::memcpy(out, kPrefix, sizeof(kPrefix) - 1);
  uint32_t p = sizeof(kPrefix) - 1;
  out[p++] = static_cast<char>('a' + (id % 23));
  out[p++] = '/';
  out[p++] = static_cast<char>('f');
  out[p++] = static_cast<char>('0' + ((id / 100) % 10));
  out[p++] = static_cast<char>('0' + ((id / 10) % 10));
  out[p++] = static_cast<char>('0' + (id % 10));
  out[p++] = '.';
  out[p++] = 'c';
  out[p++] = 'p';
  out[p++] = 'p';
  out[p++] = '\0';
}

static void init_repo(Repository &repo) {
  std::memset(repo.arena.data(), 0, repo.arena.size());
  std::fill(repo.index_buckets.begin(), repo.index_buckets.end(), 0);

  for (uint32_t i = 0; i < kBlobCount; ++i) {
    Blob &b = repo.blobs[i];
    fill_path(b.path, i);
    b.len = kBlobBytes - (i % 73);
    b.flags = static_cast<uint32_t>(next_u64() & 0xFF);
    for (uint32_t j = 0; j < b.len; ++j) {
      uint64_t x = next_u64();
      b.data[j] = static_cast<uint8_t>((x ^ (x >> 11) ^ (i * 17U) ^ (j * 31U)) & 0xFF);
    }
    b.hash = hash_bytes(b.data.data(), b.len);
  }
}

// Dispatch-heavy stage: creates broad arithmetic/control-flow opcode usage.
static uint64_t dispatch_stage(const Repository &repo) {
  uint64_t acc = 0x6a09e667f3bcc909ULL;
  for (uint32_t i = 0; i < kBlobCount; ++i) {
    const Blob &b = repo.blobs[i];
    for (uint32_t j = 0; j < b.len; ++j) {
      uint64_t v = static_cast<uint64_t>(b.data[j]) + j + (acc & 0x7fULL);
      switch ((v ^ i) & 0x0fULL) {
      case 0:
        acc ^= (v << 1);
        break;
      case 1:
        acc += (v * 3ULL);
        break;
      case 2:
        acc = (acc << 7) | (acc >> 57);
        break;
      case 3:
        acc ^= mix64(v + acc);
        break;
      case 4:
        acc -= (v * 11ULL);
        break;
      case 5:
        acc += (acc >> 9) ^ v;
        break;
      case 6:
        acc ^= (v << 17) | (v >> 47);
        break;
      case 7:
        acc = mix64(acc ^ (v * v));
        break;
      case 8:
        acc += (v + 0x9e3779b97f4a7c15ULL);
        break;
      case 9:
        acc ^= acc >> 13;
        break;
      case 10:
        acc += (acc << 5) ^ v;
        break;
      case 11:
        acc = (acc >> 3) + (v << 19);
        break;
      case 12:
        acc ^= (v * 0xc2b2ae3d27d4eb4fULL);
        break;
      case 13:
        acc += mix64(v ^ i);
        break;
      case 14:
        acc = (acc << 11) | (acc >> 53);
        break;
      default:
        acc ^= (v + (acc >> 1));
        break;
      }
    }
  }
  return mix64(acc);
}

static uint64_t memory_stage(Repository &repo) {
  uint64_t score = 0;
  uint32_t cursor = 0;
  for (uint32_t i = 0; i < kBlobCount; ++i) {
    const Blob &b = repo.blobs[i];
    const uint32_t span = b.len > 320 ? 320 : b.len;
    if (cursor + span + 128 >= repo.arena.size()) {
      cursor = static_cast<uint32_t>((cursor * 1315423911U) % (repo.arena.size() - span - 1));
    }
    std::memcpy(repo.arena.data() + cursor, b.data.data(), span);
    const uint32_t dst = static_cast<uint32_t>((cursor + 73 + i) % (repo.arena.size() - span));
    std::memmove(repo.arena.data() + dst, repo.arena.data() + cursor, span);
    score ^= hash_bytes(repo.arena.data() + dst, span);
    cursor = static_cast<uint32_t>((dst + span + 29) % (repo.arena.size() - 1));
  }
  return mix64(score ^ hash_bytes(repo.arena.data(), 4096));
}

static uint64_t simdish_stage(const Repository &repo) {
  uint64_t lane0 = 0;
  uint64_t lane1 = 0;
  uint64_t lane2 = 0;
  uint64_t lane3 = 0;
  for (uint32_t i = 0; i < kBlobCount; ++i) {
    const Blob &b = repo.blobs[i];
    uint32_t j = 0;
    for (; j + 3 < b.len; j += 4) {
      lane0 += static_cast<uint64_t>(b.data[j]) * 3ULL;
      lane1 += static_cast<uint64_t>(b.data[j + 1]) * 5ULL;
      lane2 += static_cast<uint64_t>(b.data[j + 2]) * 7ULL;
      lane3 += static_cast<uint64_t>(b.data[j + 3]) * 11ULL;
      lane0 ^= lane2 >> 7;
      lane1 ^= lane3 << 3;
      lane2 += lane0 ^ lane1;
      lane3 += lane2 ^ 0x9e3779b97f4a7c15ULL;
    }
    for (; j < b.len; ++j) {
      switch (j & 3U) {
      case 0:
        lane0 += b.data[j];
        break;
      case 1:
        lane1 += b.data[j];
        break;
      case 2:
        lane2 += b.data[j];
        break;
      default:
        lane3 += b.data[j];
        break;
      }
    }
  }
  return mix64(lane0 ^ lane1 ^ lane2 ^ lane3);
}

static uint64_t conversion_and_component_stage(const Repository &repo) {
  double io_acc = 0.0;
  double http_acc = 0.0;
  double nn_acc = 0.0;
  uint64_t text_hash = 0;

  for (uint32_t i = 0; i < kBlobCount; ++i) {
    const Blob &b = repo.blobs[i];
    const uint32_t plen = static_cast<uint32_t>(std::strlen(b.path));
    text_hash ^= hash_bytes(reinterpret_cast<const uint8_t *>(b.path), plen);
    for (uint32_t j = 0; j < b.len; ++j) {
      const double x = static_cast<double>(b.data[j]) / 255.0;
      io_acc += x * (1.0 + static_cast<double>(j & 7U));
      http_acc += x * static_cast<double>((i + j) & 31U) * 0.125;
      nn_acc += x * 0.03125 * static_cast<double>((j % 19U) + 1U);
      nn_acc -= x * 0.007;
    }
  }

  if (io_acc < 0.0)
    io_acc = -io_acc;
  if (http_acc < 0.0)
    http_acc = -http_acc;
  if (nn_acc < 0.0)
    nn_acc = -nn_acc;
  if (io_acc > 1.0e12)
    io_acc = 1.0e12;
  if (http_acc > 1.0e12)
    http_acc = 1.0e12;
  if (nn_acc > 1.0e12)
    nn_acc = 1.0e12;

  const uint64_t io_u = static_cast<uint64_t>(io_acc * 1024.0);
  const uint64_t http_u = static_cast<uint64_t>(http_acc * 1024.0);
  const uint64_t nn_u = static_cast<uint64_t>(nn_acc * 1024.0);
  return mix64(text_hash ^ mix64(io_u) ^ mix64(http_u) ^ mix64(nn_u));
}

static uint64_t tree_hash(const Repository &repo) {
  uint64_t out = 0;
  for (uint32_t i = 0; i < kBlobCount; ++i) {
    const Blob &b = repo.blobs[i];
    const uint64_t path_h = hash_bytes(reinterpret_cast<const uint8_t *>(b.path), static_cast<uint32_t>(std::strlen(b.path)));
    out ^= mix64(path_h ^ b.hash ^ b.flags);
  }
  return out;
}

static uint64_t mutate_repo(Repository &repo, uint32_t round) {
  uint64_t diff = 0;
  const uint32_t edits = 9 + (round % 13U);
  for (uint32_t e = 0; e < edits; ++e) {
    const uint32_t idx = static_cast<uint32_t>(next_u64() % kBlobCount);
    Blob &b = repo.blobs[idx];
    const uint32_t pos = static_cast<uint32_t>(next_u64() % b.len);
    const uint8_t before = b.data[pos];
    b.data[pos] ^= static_cast<uint8_t>((round * 17U + e * 29U + idx) & 0xFFU);
    if (((round + e) % 5U) == 0U && (pos + 1U) < b.len) {
      b.data[pos + 1U] = static_cast<uint8_t>((before + b.data[pos] + round + e) & 0xFFU);
    }
    b.hash = hash_bytes(b.data.data(), b.len);
    diff ^= mix64((static_cast<uint64_t>(before) << 8U) | b.data[pos]);
  }
  return diff;
}

static uint64_t indexing_stage(Repository &repo) {
  std::fill(repo.index_buckets.begin(), repo.index_buckets.end(), 0);
  for (uint32_t i = 0; i < kBlobCount; ++i) {
    const Blob &b = repo.blobs[i];
    const uint64_t key = mix64(b.hash ^ i);
    const uint32_t bucket = static_cast<uint32_t>(key & (kBuckets - 1));
    repo.index_buckets[bucket] ^= key;
  }
  uint64_t digest = 0;
  for (uint32_t i = 0; i < kBuckets; ++i) {
    digest ^= mix64(repo.index_buckets[i] + i);
  }
  return digest;
}

static uint64_t run_full_benchmark() {
  Repository repo{};
  init_repo(repo);

  uint64_t total = 0;
  total ^= dispatch_stage(repo);
  total ^= memory_stage(repo);
  total ^= simdish_stage(repo);
  total ^= conversion_and_component_stage(repo);
  total ^= indexing_stage(repo);

  uint64_t parent = 0;
  for (uint32_t rev = 0; rev < kCommitCount; ++rev) {
    const uint64_t diff = mutate_repo(repo, rev);
    const uint64_t tree = tree_hash(repo);
    const uint64_t id = mix64(tree ^ diff ^ parent ^ (rev * 0x9e3779b97f4a7c15ULL));
    repo.commits[rev] = Commit{id, parent, tree, diff, 9 + (rev % 13U)};
    parent = id;
    total ^= mix64(id + diff + tree + rev);
  }

  // Pack-like pass over commit graph and content.
  for (uint32_t i = 0; i < kCommitCount; ++i) {
    const Commit &c = repo.commits[i];
    total ^= mix64(c.id ^ c.parent ^ c.tree ^ c.diff ^ c.touched);
  }
  for (uint32_t i = 0; i < kBlobCount; ++i) {
    const Blob &b = repo.blobs[i];
    uint64_t rolling = 0;
    for (uint32_t j = 0; j < b.len; ++j) {
      rolling = (rolling << 5) ^ (rolling >> 2) ^ static_cast<uint64_t>(b.data[j] + (j & 31U));
      if ((j & 31U) == 31U) {
        total ^= mix64(rolling);
      }
    }
    total ^= mix64(rolling ^ b.hash);
  }

  return mix64(total ^ (kBlobCount * 41ULL) ^ (kCommitCount * 131ULL));
}

} // namespace

int main() {
  const uint64_t digest = run_full_benchmark();
  std::printf("wart-git-cpp-comprehensive digest=%016llx commits=%u blobs=%u\n", static_cast<unsigned long long>(digest),
              static_cast<unsigned>(kCommitCount), static_cast<unsigned>(kBlobCount));
  std::fflush(stdout);
  return 0;
}
