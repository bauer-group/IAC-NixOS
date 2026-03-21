# Secrets Management mit agenix

## Warum Secrets Management?

NixOS-Konfigurationen landen im Nix Store — der ist **world-readable**.
Passwörter, API-Keys und private Schlüssel dürfen daher **niemals** direkt
in `.nix`-Dateien stehen.

**agenix** löst das: Secrets werden mit age verschlüsselt im Git-Repo
gespeichert und erst zur Laufzeit auf dem Zielsystem entschlüsselt.

## Setup

### 1. SSH-Keys sammeln

agenix nutzt die SSH Host-Keys der Maschinen als Empfänger:

```bash
# Host-Key des Servers auslesen (Ed25519)
ssh-keyscan -t ed25519 10.0.0.1 2>/dev/null | ssh-to-age

# Oder lokal:
cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age

# Eigenen User-Key (für lokales Editieren)
cat ~/.ssh/id_ed25519.pub | ssh-to-age
```

### 2. `secrets/secrets.nix` erstellen

```nix
# secrets/secrets.nix
# Definiert WER welche Secrets entschlüsseln darf
let
  # User-Keys (können Secrets editieren)
  karl = "age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";

  # Host-Keys (können Secrets zur Laufzeit lesen)
  prod-server-01 = "age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
  prod-server-02 = "age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
  karl-desktop   = "age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";

  # Gruppen
  allServers = [ prod-server-01 prod-server-02 ];
  allHosts = allServers ++ [ karl-desktop ];
in {
  # Jedes Secret: Pfad → wer darf entschlüsseln
  "db-password.age".publicKeys       = [ karl ] ++ allServers;
  "outline-secret.age".publicKeys    = [ karl prod-server-01 ];
  "wireguard-key.age".publicKeys     = [ karl ] ++ allHosts;
  "smtp-password.age".publicKeys     = [ karl ] ++ allServers;
}
```

### 3. Secrets anlegen

```bash
cd ~/bauer-nix

# Secret erstellen (öffnet $EDITOR)
agenix -e secrets/db-password.age

# Oder aus Datei/Command:
echo "mein-geheimes-passwort" | agenix -e secrets/db-password.age

# Secret bearbeiten
agenix -e secrets/db-password.age

# Alle Secrets neu verschlüsseln (nach Key-Änderung in secrets.nix)
agenix -r
```

### 4. In NixOS-Config nutzen

```nix
# In einem Modul oder Host-Config:
{ config, ... }: {
  # Secret deklarieren
  age.secrets.db-password = {
    file = ../../secrets/db-password.age;
    owner = "postgres";     # Welcher User darf lesen
    group = "postgres";
    mode = "0400";          # Nur Eigentümer darf lesen
  };

  # Secret referenzieren (Pfad zur entschlüsselten Datei)
  services.postgresql.initialScript = pkgs.writeText "init.sql" ''
    ALTER USER myapp PASSWORD '$(cat ${config.age.secrets.db-password.path})';
  '';

  # Oder als Environment-Variable in systemd:
  systemd.services.myapp.serviceConfig = {
    EnvironmentFile = config.age.secrets.db-password.path;
  };
}
```

## Repo-Struktur mit Secrets

```
bauer-nix/
├── secrets/
│   ├── secrets.nix          # Key-Zuordnung (NICHT verschlüsselt, committen!)
│   ├── db-password.age      # Verschlüsselt (committen!)
│   ├── outline-secret.age   # Verschlüsselt (committen!)
│   └── wireguard-key.age    # Verschlüsselt (committen!)
├── modules/
│   └── ...
```

**Wichtig:** Die `.age`-Dateien sind sicher und können committet werden.
Nur wer den richtigen Private Key hat, kann sie entschlüsseln.

## Workflow

```
1. Secret anlegen:     agenix -e secrets/neues-secret.age
2. In secrets.nix:     Hosts zuordnen
3. In NixOS-Config:    age.secrets.neues-secret.file = ...
4. Deployen:           colmena apply --on @production
5. Auf dem Server:     cat /run/agenix/neues-secret  (nur als root/owner)
```

## Alternative: sops-nix

Falls du lieber sops nutzt (unterstützt auch GPG und cloud KMS):

```nix
# In flake.nix inputs:
sops-nix.url = "github:Mic92/sops-nix";

# Dann statt agenix:
sops.secrets.db-password = {
  sopsFile = ./secrets/secrets.yaml;
  owner = "postgres";
};
```

sops-nix ist flexibler (YAML/JSON/ENV-Format, mehrere KMS-Backends),
agenix ist simpler (nur age, ein Secret pro Datei).
