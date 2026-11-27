use std::sync::Once;

use crossbeam_channel::{bounded, Receiver, Sender};
use log::{Level, Metadata, Record};

pub type DfLogReceiver = Receiver<LogMessage>;

pub type LogMessage = (Level, String, Option<String>, Option<u32>); // level, message, module, lineno
const LOG_CHANNEL_CAPACITY: usize = 1024;

pub struct DfLogger {
    sender: Sender<LogMessage>,
    level: Level,
}

static LOGGER_INIT: Once = Once::new();

impl DfLogger {
    pub fn build(level: Level) -> (DfLogger, DfLogReceiver) {
        let (sender, receiver) = bounded(LOG_CHANNEL_CAPACITY);
        let logger = DfLogger { sender, level };
        (logger, receiver)
    }
}

impl log::Log for DfLogger {
    fn enabled(&self, metadata: &Metadata) -> bool {
        metadata.level() <= self.level && metadata.target().starts_with("df:")
    }

    fn log(&self, record: &Record) {
        if self.enabled(record.metadata()) {
            // Logging must never block DSP work or grow memory without bound.
            // Drop the newest record when the diagnostics consumer falls behind.
            let _ = self.sender.try_send((
                record.level(),
                format!("{}", record.args()),
                record
                    .module_path()
                    .map(|f| f.replace("::reexport_dataset_modules:", "")),
                record.line(),
            ));
        }
    }

    fn flush(&self) {}
}

pub fn init_logger(logger: DfLogger) {
    LOGGER_INIT.call_once(|| {
        let level = logger.level;
        log::set_boxed_logger(Box::new(logger)).expect("Could not set logger");
        log::set_max_level(level.to_level_filter());
    });
}
