class CITimeoutException : System.Exception {
    CITimeoutException([string] $msg) : base($msg) {}
    CITimeoutException([string] $msg, [System.Exception] $inner) : base($msg, $inner) {}
}
