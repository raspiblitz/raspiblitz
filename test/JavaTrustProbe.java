// Real JSSE TLS and PKIX controls. Uses only public certificates as anchors.
import java.io.*;
import java.net.*;
import java.nio.file.*;
import java.security.*;
import java.security.cert.*;
import java.util.*;
import javax.net.ssl.*;

public class JavaTrustProbe {
    static final char[] PASSWORD = "changeit".toCharArray();
    static KeyStore load(String path) throws Exception {
        KeyStore store = KeyStore.getInstance("JKS");
        try (InputStream in = Files.newInputStream(Path.of(path))) { store.load(in, PASSWORD); }
        return store;
    }
    public static void main(String[] args) throws Exception {
        CertificateFactory cf = CertificateFactory.getInstance("X.509");
        if (args[0].equals("build")) {
            KeyStore store = KeyStore.getInstance("JKS");
            store.load(null, PASSWORD);
            int i = 0;
            try (InputStream in = Files.newInputStream(Path.of(args[1]))) {
                for (java.security.cert.Certificate cert : cf.generateCertificates(in))
                    store.setCertificateEntry("public-" + i++, cert);
            }
            try (OutputStream out = Files.newOutputStream(Path.of(args[2]))) { store.store(out, PASSWORD); }
            System.out.println("BUILT " + i + " public anchors");
            return;
        }
        KeyStore store = load(args[1]);
        if (args[0].equals("chain")) {
            Collection<? extends java.security.cert.Certificate> certs;
            try (InputStream in = Files.newInputStream(Path.of(args[2]))) { certs = cf.generateCertificates(in); }
            X509CertSelector target = new X509CertSelector();
            target.setCertificate((X509Certificate) certs.iterator().next());
            PKIXBuilderParameters params = new PKIXBuilderParameters(store, target);
            params.setRevocationEnabled(false);
            params.addCertStore(CertStore.getInstance("Collection", new CollectionCertStoreParameters(certs)));
            try {
                CertPathBuilder.getInstance("PKIX").build(params);
                System.out.println("ACCEPT");
            } catch (CertPathBuilderException e) {
                System.out.println("REJECT " + e.getClass().getSimpleName() + ": " + e.getMessage());
                System.exit(2);
            }
            return;
        }
        TrustManagerFactory tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        tmf.init(store);
        SSLContext ctx = SSLContext.getInstance("TLS");
        ctx.init(null, tmf.getTrustManagers(), null);
        HttpsURLConnection connection = (HttpsURLConnection) URI.create(args[2]).toURL().openConnection();
        connection.setSSLSocketFactory(ctx.getSocketFactory());
        connection.setConnectTimeout(15000);
        connection.setReadTimeout(15000);
        try {
            System.out.println("ACCEPT HTTP " + connection.getResponseCode());
        } catch (SSLHandshakeException e) {
            boolean validation = false;
            for (Throwable cause = e; cause != null; cause = cause.getCause())
                if (cause instanceof CertPathValidatorException || cause instanceof CertPathBuilderException)
                    validation = true;
            if (!validation) throw e;
            System.out.println("REJECT CERTIFICATE " + e.getMessage());
            System.exit(2);
        } finally { connection.disconnect(); }
    }
}
