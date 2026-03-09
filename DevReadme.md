# Connector development

If you want to modify the connector, you'll have to install:

- [Visual Studio 2019](https://visualstudio.microsoft.com/fr/downloads/)
- [Power Query SDK addon for vsCode](https://docs.microsoft.com/en-us/power-query/installingsdk)

You can then open the solution located in [Braincube.sln](Braincube.sln). You should be able to build immediately.

Debugging it is HARD. I'll let the reader find out if he can easily. I couldn't.

## For test in local

- You have to enable the "Uncertified connectors" in the Security Options of Power BI in Options >> Global >> Security >> Data
  Extensions (See [README.md](README.md#install-the-connector) for more detail)
- After you compile your code, go to Braincube\bin\Debug of your source directory
- Copy Braincube.mez to %USERHOME%\Documents\Power BI Desktop\Custom Connectors (Create the folder if it doesn't exist)
- Advice: You can update the .mez without restarting Power BI Desktop ;-)

## delete the apikey

In Power BI, API keys are saved as "metadata". To delete it when the API key popup appears in the Braincube connector, go to "Files >> Parameters >> parameters of data src" and delete the saved value.

## Almost debug ...

- In the code add Diagnostics.Trace(...), but you need to return it in a variable, and this variable must be "let" at the end of your query ...
- For example, at the end of method GetVariableContent, you can add this line: tmp = Diagnostics.Trace(TraceLevel.Information, "
  MGI :: " & Date.ToText(endDate, "yyyy/MM/dd "), () => result, true)
  Then update the last line from "in result" to "in tmp".
- To see the log, you need to activate diagnostics in your Power BI Desktop (Warning: Enable tracing option will be reset when the
  Power BI Desktop instance is closed. To enable tracing, the option needs to be manually set every time Power BI Desktop is
  opened.)
  ![alt text](img/enable-tracing-powerbi.png)
- After you execute the code with your "log" , you need to go to C:\Users\User\Microsoft\Power BI Desktop Store App\Traces (Or in
  same windows for activate it, you have a link "go to traces directory")
- In this dir, you find a file "Microsoft.Mashup.Container.NetFXwithmanynumber" with your log.
- Advice: Tag your log with a simple identifier (like your initials), because this file contains many lines ;-)
- Warning: The trace works only the log contains "real" powerBi text :-(

# Virtualbox configuration

## Screen resolution

- In image when is launched, go to menu "périphériques", and clic on "Insérer l'image Cd des additions invités"
- Install all
- After the reboot you can up the screen resolution

# Connector signage

This connector is self-signed with a developer certificate. This allows clients to trust that the extension was actually created
by us (Braincube) by verifying the signature of the extension against a thumbprint.

This all starts at this page: https://docs.microsoft.com/en-us/power-query/handlingconnectorsigning

## Signing Cert

/!\ To retrieve the certificate, contact a SysAdmin and ask him to sign the certificate. The certificate is located in the admin's
password stash

You will first have to generate a signing certificate, if there is not one already existing (hint: it should already exist if
there has been at least one public release of the Braincube connector).

In any case, you should generate it like this:

```powershell
New-SelfSignedCertificate -Type CodeSigningCert -FriendlyName "BraincubeSigning" -CertStoreLocation Cert:\CurrentUser\My -Subject "Braincube Connector Signing Cert"


   PSParentPath : Microsoft.PowerShell.Security\Certificate::CurrentUser\My

Thumbprint                                Subject
----------                                -------
xxx                                       CN=Braincube Connector Signing Cert

```

Once created, you have to export it to PFX format:

https://superuser.com/a/1099602

In a powershell:

```powershell
cd Cert:\CurrentUser\My\
dir # should show the braincube certificate, copy its ID
# now export the certificate and its private key to your home directory:
Export-PfxCertificate -Cert .\THE_ID_OF_THE_CERT -FilePath $home\cert.pfx -Password (ConvertTo-SecureString -String 'A_STRONG_PASSWORD' -AsPlainText -Force)
```

## Sign the actual exe

To sign the connector, you need MakePQX from the Power Query SDK Tools:

1. Download the **Microsoft.PowerQuery.SdkTools** NuGet package from https://www.nuget.org/packages/Microsoft.PowerQuery.SdkTools
2. Extract it and locate MakePQX at `.\tools\MakePQX.exe`

Then, build the solution in Release mode and run:

```powershell
C:\path\to\MakePQX.exe pack -mz .\Braincube\bin\Release\Braincube.mez -c $home\cert.pfx -p 'YOUR_STRONG_PASSWORD' -t Braincube.pqx
```

Replace `C:\path\to\` with the directory where you extracted MakePQX.

This creates a signed `Braincube.pqx` file. You can verify it with:

```powershell
C:\path\to\MakePQX.exe verify .\Braincube.pqx

{
  "SignatureStatus": "Success",
  "CertificateStatus": [
    {
      "Issuer": "CN=Braincube Connector Signing Cert",
      "Thumbprint": "YOUR THUMBPRINT",
      "Subject": "CN=Braincube Connector Signing Cert",
      "NotBefore": "2021-03-22T11:53:10+01:00",
      "NotAfter": "2022-03-22T12:13:10+01:00",
      "Valid": false,
      "Parent": null,
      "Status": "UntrustedRoot"
    }
  ]
}
```

# Building the Connector (Linux)

## Prerequisites

- Linux/Ubuntu with `zip` installed
- The `build.sh` script

## Build Steps

```bash
# Make the script executable (first time only)
chmod +x build.sh

# Build with default name (creates Braincube.mez)
./build.sh

# Build with custom version name (creates Braincube3.2.0.mez)
./build.sh Braincube3.2.0
```

The `.mez` file is a simple ZIP archive containing the connector code.
