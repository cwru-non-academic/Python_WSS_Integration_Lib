"""Small logger wrapper.

This is intentionally minimal; the primary logging path in this repo is the bridged
C# sink in :mod:`wss_py_wrapper.log_sink`.
"""

from .log_sink import LogSink


class Logger:
    """Write log lines to a :class:`~wss_py_wrapper.log_sink.LogSink`.

    :param sink: Target sink.
    """

    def __init__(self, sink: LogSink) -> None:
        self._sink = sink

    def info(self, message: str) -> None:
        """Write an INFO message.

        :param message: Message text.
        """
        self._sink.write("INFO", message)

    def warning(self, message: str) -> None:
        """Write a WARN message.

        :param message: Message text.
        """
        self._sink.write("WARN", message)

    def error(self, message: str) -> None:
        """Write an ERROR message.

        :param message: Message text.
        """
        self._sink.write("ERROR", message)
