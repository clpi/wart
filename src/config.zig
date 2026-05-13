const types = @import("config/types.zig");
const file = @import("config/file.zig");

pub const Config = types.Config;
pub const ConfigKeyError = types.ConfigKeyError;
pub const persisted_keys = types.persisted_keys;
pub const config_filename = file.config_filename;
pub const defaultConfigDir = file.defaultConfigDir;
pub const defaultConfigFilePath = file.defaultConfigFilePath;
pub const ensureDefaultConfig = file.ensureDefaultConfig;
pub const readRawConfig = file.readRawConfig;
pub const saveToDisk = file.saveToDisk;
pub const resetConfig = file.resetConfig;

/// Load configuration from disk and auto-create defaults when missing.
pub const loadFromDisk = file.loadFromDisk;
