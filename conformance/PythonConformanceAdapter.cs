using Python.Runtime;
using Wss.Testing;

// Only fixture factory/alias changes. All commands enter production Python;
// the canonical evaluators and assertions remain managed and unchanged.
internal sealed class DotNetConformanceAdapter : IDisposable
{
    private static readonly object RuntimeGate = new();
    private readonly PyObject _controller;

    internal DotNetConformanceAdapter(string directory)
    {
        lock (RuntimeGate)
        {
            if (!PythonEngine.IsInitialized)
            {
                Runtime.PythonDLL = Environment.GetEnvironmentVariable("PYTHON_DLL")
                    ?? throw new InvalidOperationException("Exact Python DLL required.");
                PythonEngine.PythonHome = Environment.GetEnvironmentVariable("PYTHON_HOME")!;
                PythonEngine.Initialize();
                PythonEngine.BeginAllowThreads();
            }
        }
        using (Py.GIL())
        {
            dynamic sys = Py.Import("sys");
            sys.path.insert(0, Environment.GetEnvironmentVariable("WSS_PYTHON_SOURCE")!);
#if CLI_CONFORMANCE
            sys.path.insert(0, Environment.GetEnvironmentVariable("WSS_CLI_SOURCE")!);
#endif
            dynamic pathlib = Py.Import("pathlib");
            dynamic wrapper = Py.Import("wss_py_wrapper");
            using PyObject config = wrapper.WssConfig(
                config_path: pathlib.Path(directory),
                log_path: pathlib.Path(Path.Combine(directory, "python.log")),
                cs_lib_dir: pathlib.Path(Environment.GetEnvironmentVariable("WSS_PYTHON_PAYLOAD")!),
                conformance_mode: true, max_setup_tries: 1, tick_interval_ms: 1);
#if CLI_CONFORMANCE
            dynamic cli = Py.Import("wss_cli.main");
            _controller = cli.create_controller(config);
#else
            _controller = wrapper.StimulationController(config);
#endif
        }
    }

    public void Initialize() { using (Py.GIL()) ((dynamic)_controller).Initialize(); }
    public bool Ready() { using (Py.GIL()) return (bool)((dynamic)_controller).Ready(); }
    public bool Started() { using (Py.GIL()) return (bool)((dynamic)_controller).Started(); }
    public bool TryGetConformance(out IWssConformance conformance)
    {
        using (Py.GIL())
        {
            using PyObject result = ((dynamic)_controller).GetConformance();
            if (result.IsNone()) { conformance = null!; return false; }
            conformance = result.As<IWssConformance>();
            return true;
        }
    }
    public void StimulateAnalog(string channel, int pw, int amp, int ipi)
    { using (Py.GIL()) ((dynamic)_controller).StimulateAnalog(channel, pw, amp, ipi); }
    public void StimulateNormalized(string channel, float magnitude)
    { using (Py.GIL()) ((dynamic)_controller).StimulateNormalized(channel, magnitude); }
    public void UpdateEventRatio(int target, int ratio, int eventId)
    { using (Py.GIL()) ((dynamic)_controller).UpdateEventRatio(target, ratio, eventId); }
    public void StopStimulation(int target)
    { using (Py.GIL()) ((dynamic)_controller).StopStimulation(target); }
    public void Dispose()
    {
        using (Py.GIL())
        {
            ((dynamic)_controller).Shutdown();
            _controller.Dispose();
        }
    }
}
