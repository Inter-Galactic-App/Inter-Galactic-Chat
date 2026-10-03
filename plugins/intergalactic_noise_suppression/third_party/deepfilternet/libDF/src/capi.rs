use std::boxed::Box;
use std::ffi::{c_char, c_float, c_uint, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use std::str::FromStr;

use anyhow::{Context, Result};
use crossbeam_channel::TryRecvError;
use ndarray::prelude::*;

use crate::logging::*;
use crate::tract::*;

pub struct DFState {
    m: crate::tract::DfTract,
    logger: Option<DfLogReceiver>,
}

impl DFState {
    fn new(
        model_path: &str,
        channels: usize,
        atten_lim: f32,
        log_level: Option<&str>,
    ) -> Result<Self> {
        let logger = if let Some(level) = log_level {
            let level = log::Level::from_str(level).context("Could not parse log level")?;
            let (logger, log_receiver) = DfLogger::build(level);
            init_logger(logger);
            Some(log_receiver)
        } else {
            None
        };
        let mut r_params = RuntimeParams::default_with_ch(channels); //channel
        r_params = r_params.with_atten_lim(atten_lim).with_thresholds(
            -15.0f32, //min_db_thresh
            35.0f32,  //max_db_erb_thresh
            35.0f32,  //max_db_df_thresh
        );
        r_params = r_params.with_post_filter(0.0f32); //post_filter_beta
        r_params = r_params.with_mask_reduce(ReduceMask::MAX); //reduce_mask
        let df_params =
            DfParams::new(PathBuf::from(model_path)).context("Could not load model from path")?;
        let m = DfTract::new(df_params, &r_params)
            .context("Could not initialize DeepFilter runtime")?;
        Ok(DFState { m, logger })
    }
    /// Returns the next log message as String
    fn get_next_log_message(&mut self) -> Option<String> {
        if let Some(logger) = self.logger.as_ref() {
            match logger.try_recv() {
                Ok(m) => {
                    let mut prefix: String = String::new();
                    if let Some(module) = m.2 {
                        prefix.push_str(&module);
                        if let Some(lineno) = m.3 {
                            prefix.push(':');
                            prefix.push_str(&lineno.to_string())
                        }
                    }
                    let mut message = m.0.as_str().to_owned() + " | " + &m.1;
                    if !prefix.is_empty() {
                        message = prefix + " | " + &message
                    }
                    return Some(message);
                }
                Err(TryRecvError::Empty) => return None,
                Err(TryRecvError::Disconnected) => {
                    eprintln!("DF logger disconnected unexpectetly!");
                    return None;
                }
            }
        }
        None
    }
    fn boxed(self) -> Box<DFState> {
        Box::new(self)
    }
}

/// Create a DeepFilterNet Model
///
/// Args:
///     - path: File path to a DeepFilterNet tar.gz onnx model
///     - atten_lim: Attenuation limit in dB.
///
/// Returns:
///     - DF state doing the full processing: stft, DNN noise reduction, istft.
#[no_mangle]
pub unsafe extern "C" fn df_create(
    path: *const c_char,
    // channels: usize,
    atten_lim: f32,
    log_level: *const c_char,
) -> *mut DFState {
    if path.is_null() {
        return std::ptr::null_mut();
    }
    let path = match CStr::from_ptr(path).to_str() {
        Ok(path) => path,
        Err(_) => return std::ptr::null_mut(),
    };
    let log_level = if log_level.is_null() {
        None
    } else {
        match CStr::from_ptr(log_level).to_str() {
            Ok(a) => Some(a),
            Err(e) => {
                eprintln!("Could not parse log_level {}", e);
                None
            }
        }
    };
    // libDF model loading can panic on structurally valid gzip archives whose
    // contents are not a model. Never let that unwind through the C ABI:
    // callers use null as the fail-open initialization failure signal.
    match catch_unwind(AssertUnwindSafe(|| {
        DFState::new(path, 1, atten_lim, log_level).map(DFState::boxed)
    })) {
        Ok(Ok(df)) => Box::into_raw(df),
        Ok(Err(error)) => {
            eprintln!("Could not create DeepFilter runtime: {error:#}");
            std::ptr::null_mut()
        }
        Err(_) => {
            eprintln!("DeepFilter runtime creation panicked");
            std::ptr::null_mut()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use flate2::write::GzEncoder;
    use flate2::Compression;
    use std::fs;
    use std::io::Write;
    use std::process::Command;

    #[test]
    fn corrupt_but_gzip_valid_model_fails_closed_at_c_abi_boundary() {
        const CHILD_ENV: &str = "INTERGALACTIC_DF_CORRUPT_MODEL_TEST_CHILD";
        if std::env::var_os(CHILD_ENV).is_none() {
            let status = Command::new(std::env::current_exe().expect("current test executable"))
                .arg("corrupt_but_gzip_valid_model_fails_closed_at_c_abi_boundary")
                .arg("--nocapture")
                .env(CHILD_ENV, "1")
                .status()
                .expect("run corrupt model test in child process");
            assert!(status.success(), "corrupt model child failed: {status}");
            return;
        }

        let fixture_path = std::env::temp_dir().join(format!(
            "intergalactic-deepfilter-corrupt-model-{}.tar.gz",
            std::process::id()
        ));
        let file = fs::File::create(&fixture_path).expect("create corrupt model fixture");
        let mut gzip = GzEncoder::new(file, Compression::default());
        gzip.write_all(b"not a DeepFilterNet model")
            .expect("write corrupt model fixture");
        gzip.finish().expect("finish corrupt model fixture");

        let path = CString::new(fixture_path.to_string_lossy().as_bytes()).expect("path CString");
        let state = unsafe { df_create(path.as_ptr(), 60.0, std::ptr::null()) };
        assert!(state.is_null());
        fs::remove_file(fixture_path).expect("remove corrupt model fixture");
    }
}

/// Get DeepFilterNet frame size in samples.
#[no_mangle]
pub unsafe extern "C" fn df_get_frame_length(st: *mut DFState) -> usize {
    let state = st.as_mut().expect("Invalid pointer");
    state.m.hop_size
}

/// Get the next log message. Must be freed via `df_free_log_msg(ptr)`
#[no_mangle]
pub unsafe extern "C" fn df_next_log_msg(st: *mut DFState) -> *mut c_char {
    let state = st.as_mut().expect("Invalid pointer");
    let msg = state.get_next_log_message();
    if let Some(msg) = msg {
        let c_msg = CString::new(msg).expect("Failed to convert log message to CString");
        c_msg.into_raw()
    } else {
        std::ptr::null_mut()
    }
}

#[no_mangle]
pub unsafe extern "C" fn df_free_log_msg(ptr: *mut c_char) {
    let _ = CString::from_raw(ptr);
}

/// Set DeepFilterNet attenuation limit.
///
/// Args:
///     - lim_db: New attenuation limit in dB.
#[no_mangle]
pub unsafe extern "C" fn df_set_atten_lim(st: *mut DFState, lim_db: f32) {
    let state = st.as_mut().expect("Invalid pointer");
    state.m.set_atten_lim(lim_db)
}

/// Set DeepFilterNet post filter beta. A beta of 0 disables the post filter.
///
/// Args:
///     - beta: Post filter attenuation. Suitable range between 0.05 and 0;
#[no_mangle]
pub unsafe extern "C" fn df_set_post_filter_beta(st: *mut DFState, beta: f32) {
    let state = st.as_mut().expect("Invalid pointer");
    state.m.set_pf_beta(beta)
}

/// Processes a chunk of samples.
///
/// Args:
///     - df_state: Created via df_create()
///     - input: Input buffer of length df_get_frame_length()
///     - output: Output buffer of length df_get_frame_length()
///
/// Returns:
///     - Local SNR of the current frame.
#[no_mangle]
pub unsafe extern "C" fn df_process_frame(
    st: *mut DFState,
    input: *mut c_float,
    output: *mut c_float,
) -> c_float {
    let state = st.as_mut().expect("Invalid pointer");
    let input = ArrayView2::from_shape_ptr((1, state.m.hop_size), input);
    let output = ArrayViewMut2::from_shape_ptr((1, state.m.hop_size), output);

    state
        .m
        .process(input, output)
        .expect("Failed to process DF frame")
}

/// Processes a filter bank sample and return raw gains and DF coefs.
///
/// Args:
///     - df_state: Created via df_create()
///     - input: Spectrum of shape `[n_freqs, 2]`.
///     - out_gains_p: Output buffer of real-valued ERB gains of shape `[nb_erb]`. This function
///         may set this pointer to NULL if the local SNR is greater 30 dB. No gains need to be
///         applied then.
///     - out_coefs_p: Output buffer of complex-valued DF coefs of shape `[df_order, nb_df_freqs, 2]`.
///         This function may set this pointer to NULL if the local SNR is greater 20 dB. No DF
///         coefficients need to be applied.
///
/// Returns:
///     - Local SNR of the current frame.
#[no_mangle]
pub unsafe extern "C" fn df_process_frame_raw(
    st: *mut DFState,
    input: *mut c_float,
    out_gains_p: *mut *mut c_float,
    out_coefs_p: *mut *mut c_float,
) -> c_float {
    let state = st.as_mut().expect("Invalid pointer");
    let input = ArrayView2::from_shape_ptr((1, state.m.n_freqs), input);
    state
        .m
        .set_spec_buffer(input)
        .expect("Failed to set input spectrum");
    let (lsnr, gains, coefs) = state
        .m
        .process_raw()
        .expect("Failed to process DF spectral frame");
    let mut out_gains = ArrayViewMut2::from_shape_ptr((1, state.m.nb_erb), *out_gains_p);
    let mut out_coefs =
        ArrayViewMut4::from_shape_ptr((1, state.m.df_order, state.m.nb_df, 2), *out_coefs_p);
    if let Some(gains) = gains {
        out_gains.assign(&gains.to_array_view().unwrap());
    } else {
        *out_gains_p = std::ptr::null_mut();
    }
    if let Some(coefs) = coefs {
        out_coefs.assign(&coefs.to_array_view().unwrap());
    } else {
        *out_coefs_p = std::ptr::null_mut();
    }
    lsnr
}

// file.rs
#[repr(C)]
pub struct DynArray {
    array: *mut c_uint,
    length: c_uint,
}

/// Get size of DeepFilter coefficients
pub unsafe extern "C" fn df_coef_size(st: *const DFState) -> DynArray {
    let state = st.as_ref().expect("Invalid pointer");
    let mut shape = vec![
        state.m.ch as u32,
        state.m.df_order as u32,
        state.m.n_freqs as u32,
        2,
    ];
    let ret = DynArray {
        array: shape.as_mut_ptr(),
        length: shape.len() as u32,
    };
    std::mem::forget(shape);
    ret
}
/// Get size ERB gains
pub unsafe extern "C" fn df_gain_size(st: *const DFState) -> DynArray {
    let state = st.as_ref().expect("Invalid pointer");
    let mut shape = vec![state.m.ch as u32, state.m.nb_erb as u32];
    let ret = DynArray {
        array: shape.as_mut_ptr(),
        length: shape.len() as u32,
    };
    std::mem::forget(shape);
    ret
}

/// Free a DeepFilterNet Model
#[no_mangle]
pub unsafe extern "C" fn df_free(model: *mut DFState) {
    let _ = Box::from_raw(model);
}
