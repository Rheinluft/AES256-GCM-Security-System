if (-not ('D2xxSerialTransport' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public sealed class D2xxSerialTransport : IDisposable
{
    private const uint FtOk = 0;
    private const uint OpenBySerialNumber = 1;
    private const uint PurgeRx = 1;
    private const uint PurgeTx = 2;
    private readonly string serialNumber;
    private IntPtr handle = IntPtr.Zero;
    private bool dtrEnable;
    private bool rtsEnable;

    public int ReadTimeout { get; set; }
    public int WriteTimeout { get; set; }

    public bool DtrEnable {
        get { return dtrEnable; }
        set {
            dtrEnable = value;
            if (handle != IntPtr.Zero)
                Check(value ? FT_SetDtr(handle) : FT_ClrDtr(handle), "DTR");
        }
    }

    public bool RtsEnable {
        get { return rtsEnable; }
        set {
            rtsEnable = value;
            if (handle != IntPtr.Zero)
                Check(value ? FT_SetRts(handle) : FT_ClrRts(handle), "RTS");
        }
    }

    public D2xxSerialTransport(string serialNumber)
    {
        if (String.IsNullOrWhiteSpace(serialNumber))
            throw new ArgumentException("D2XX serial number is required", "serialNumber");
        this.serialNumber = serialNumber;
        ReadTimeout = 100;
        WriteTimeout = 1000;
    }

    public void Open()
    {
        Check(FT_OpenEx(serialNumber, OpenBySerialNumber, out handle), "FT_OpenEx");
        try {
            Check(FT_ResetDevice(handle), "FT_ResetDevice");
            Check(FT_SetBaudRate(handle, 115200), "FT_SetBaudRate");
            Check(FT_SetDataCharacteristics(handle, 8, 0, 0), "FT_SetDataCharacteristics");
            Check(FT_SetFlowControl(handle, 0, 0, 0), "FT_SetFlowControl");
            Check(FT_SetTimeouts(handle, (uint)ReadTimeout, (uint)WriteTimeout), "FT_SetTimeouts");
            Check(dtrEnable ? FT_SetDtr(handle) : FT_ClrDtr(handle), "DTR");
            Check(rtsEnable ? FT_SetRts(handle) : FT_ClrRts(handle), "RTS");
        } catch {
            Close();
            throw;
        }
    }

    public void DiscardInBuffer()
    {
        EnsureOpen();
        Check(FT_Purge(handle, PurgeRx), "FT_Purge(RX)");
    }

    public string ReadExisting()
    {
        EnsureOpen();
        uint queued;
        Check(FT_GetQueueStatus(handle, out queued), "FT_GetQueueStatus");
        if (queued == 0)
            return String.Empty;
        byte[] buffer = new byte[queued];
        uint read;
        Check(FT_Read(handle, buffer, queued, out read), "FT_Read");
        return Encoding.ASCII.GetString(buffer, 0, (int)read);
    }

    public void Write(string value)
    {
        EnsureOpen();
        byte[] buffer = Encoding.ASCII.GetBytes(value ?? String.Empty);
        uint written;
        Check(FT_Write(handle, buffer, (uint)buffer.Length, out written), "FT_Write");
        if (written != buffer.Length)
            throw new InvalidOperationException("D2XX short write");
    }

    public void Close()
    {
        if (handle == IntPtr.Zero)
            return;
        IntPtr closing = handle;
        handle = IntPtr.Zero;
        Check(FT_Close(closing), "FT_Close");
    }

    public void Dispose() { Close(); }

    private void EnsureOpen()
    {
        if (handle == IntPtr.Zero)
            throw new InvalidOperationException("D2XX transport is not open");
    }

    private static void Check(uint status, string operation)
    {
        if (status != FtOk)
            throw new InvalidOperationException(operation + " failed: FT_STATUS=" + status);
    }

    [DllImport("ftd2xx.dll", CharSet = CharSet.Ansi)]
    private static extern uint FT_OpenEx(string argument, uint flags, out IntPtr handle);
    [DllImport("ftd2xx.dll")] private static extern uint FT_Close(IntPtr handle);
    [DllImport("ftd2xx.dll")] private static extern uint FT_ResetDevice(IntPtr handle);
    [DllImport("ftd2xx.dll")] private static extern uint FT_SetBaudRate(IntPtr handle, uint baudRate);
    [DllImport("ftd2xx.dll")] private static extern uint FT_SetDataCharacteristics(IntPtr handle, byte wordLength, byte stopBits, byte parity);
    [DllImport("ftd2xx.dll")] private static extern uint FT_SetFlowControl(IntPtr handle, ushort flowControl, byte xon, byte xoff);
    [DllImport("ftd2xx.dll")] private static extern uint FT_SetTimeouts(IntPtr handle, uint readTimeout, uint writeTimeout);
    [DllImport("ftd2xx.dll")] private static extern uint FT_Purge(IntPtr handle, uint mask);
    [DllImport("ftd2xx.dll")] private static extern uint FT_GetQueueStatus(IntPtr handle, out uint queued);
    [DllImport("ftd2xx.dll")] private static extern uint FT_Read(IntPtr handle, byte[] buffer, uint bytesToRead, out uint bytesRead);
    [DllImport("ftd2xx.dll")] private static extern uint FT_Write(IntPtr handle, byte[] buffer, uint bytesToWrite, out uint bytesWritten);
    [DllImport("ftd2xx.dll")] private static extern uint FT_SetDtr(IntPtr handle);
    [DllImport("ftd2xx.dll")] private static extern uint FT_ClrDtr(IntPtr handle);
    [DllImport("ftd2xx.dll")] private static extern uint FT_SetRts(IntPtr handle);
    [DllImport("ftd2xx.dll")] private static extern uint FT_ClrRts(IntPtr handle);
}
'@
}
