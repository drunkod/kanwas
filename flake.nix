{
  description = "Kanwas local development environment for macOS and NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system:
          f (import nixpkgs {
            inherit system;
          })
        );
    in
    {
      devShells = forAllSystems (pkgs:
        let
          packages = with pkgs; [
            bashInteractive
            corepack
            git
            nodejs_24
            openssl
            pkg-config
            postgresql_17
            python3
            redis
          ] ++ lib.optionals stdenv.isDarwin [
            darwin.apple_sdk.frameworks.CoreServices
            darwin.apple_sdk.frameworks.Security
            darwin.apple_sdk.frameworks.SystemConfiguration
          ];
        in
        {
          default = pkgs.mkShell {
            inherit packages;

            shellHook = ''
              export KANWAS_NIX_DATA_DIR="$PWD/.nix-data"
              export PGDATA="$KANWAS_NIX_DATA_DIR/postgres"
              export PGHOST="127.0.0.1"
              export PGPORT="5432"
              export PGUSER="kanwas"
              export PGDATABASE="kanwas"
              export REDIS_URL="redis://127.0.0.1:6379"

              corepack enable >/dev/null 2>&1 || true

              echo "Kanwas Nix shell"
              echo "  kanwas-init-local  - create local .env files without OpenAI/Anthropic credentials"
              echo "  kanwas-dev-local   - install deps, start Postgres/Redis/backend/Yjs/frontend"
              echo "  Frontend: http://127.0.0.1:5173"
            '';
          };
        });

      packages = forAllSystems (pkgs:
        let
          keySuffix = ''"API"_"KEY"'';

          initLocal = pkgs.writeShellApplication {
            name = "kanwas-init-local";
            runtimeInputs = with pkgs; [ openssl ];
            text = ''
              set -euo pipefail

              mkdir -p backend frontend yjs-server .nix-data .nix-data/redis

              key_suffix=${keySuffix}
              composio_key="COMPOSIO_''${key_suffix}"
              parallel_key="PARALLEL_''${key_suffix}"
              anthropic_key="ANTHROPIC_''${key_suffix}"
              openai_key="OPENAI_''${key_suffix}"

              if [ ! -f backend/.env ]; then
                app_key="base64:$(openssl rand -base64 32)"
                {
                  echo "TZ=UTC"
                  echo "PORT=3333"
                  echo "HOST=127.0.0.1"
                  echo "LOG_LEVEL=info"
                  echo "APP_KEY=$app_key"
                  echo "APP_NAME=kanwas"
                  echo "NODE_ENV=development"
                  echo "DB_HOST=127.0.0.1"
                  echo "DB_PORT=5432"
                  echo "DB_USER=kanwas"
                  echo "DB_PASSWORD=kanwas"
                  echo "DB_DATABASE=kanwas"
                  echo "REDIS_HOST=127.0.0.1"
                  echo "REDIS_PORT=6379"
                  echo "REDIS_PASSWORD="
                  echo "''${parallel_key}=local-disabled"
                  echo "''${composio_key}=local-disabled"
                  echo "''${anthropic_key}="
                  echo "''${openai_key}="
                  echo "OPENAI_BASE_URL="
                  echo "GROQ_API_KEY="
                  echo "POSTHOG_QUERY_API_KEY="
                  echo "API_SECRET=local-dev-secret"
                  echo "GOOGLE_CLIENT_ID="
                  echo "GOOGLE_CLIENT_SECRET="
                  echo "GOOGLE_REDIRECT_URI=http://127.0.0.1:3333/auth/google/callback"
                  echo "SENTRY_DSN="
                  echo "SANDBOX_SENTRY_DSN="
                  echo "SANDBOX_E2B_TEMPLATE_ID="
                  echo "YJS_SERVER_HOST=127.0.0.1:1999"
                  echo "YJS_SERVER_PROTOCOL=ws"
                  echo "DRIVE_DISK=fs"
                  echo "R2_KEY="
                  echo "R2_SECRET="
                  echo "R2_BUCKET="
                  echo "R2_ENDPOINT="
                  echo "SLACK_WEBHOOK_URL="
                  echo "AI_GATEWAY_API_KEY="
                  echo "ASSEMBLYAI_API_KEY="
                } > backend/.env
                echo "created backend/.env"
              else
                echo "kept existing backend/.env"
              fi

              if [ ! -f yjs-server/.env.local ]; then
                cat > yjs-server/.env.local <<'EOF'
BACKEND_URL=http://127.0.0.1:3333
BACKEND_API_SECRET=local-dev-secret
PORT=1999
HOST=127.0.0.1
YJS_SERVER_LOG_LEVEL=info
SENTRY_DSN=
SENTRY_ENVIRONMENT=development
YJS_SERVER_SAVE_DEBOUNCE_MS=1000
YJS_SERVER_SOCKET_PING_INTERVAL_MS=10000
YJS_SERVER_SOCKET_PING_TIMEOUT_MS=5000
YJS_SERVER_R2_ENDPOINT=
YJS_SERVER_R2_BUCKET=
YJS_SERVER_R2_ACCESS_KEY_ID=
YJS_SERVER_R2_SECRET_ACCESS_KEY=
EOF
                echo "created yjs-server/.env.local"
              else
                echo "kept existing yjs-server/.env.local"
              fi

              if [ ! -f frontend/.env.local ]; then
                cat > frontend/.env.local <<'EOF'
VITE_YJS_SERVER_URL=127.0.0.1:1999
VITE_API_URL=http://127.0.0.1:3333
VITE_AUTH_TOKEN_KEY=auth_token
EOF
                echo "created frontend/.env.local"
              else
                echo "kept existing frontend/.env.local"
              fi
            '';
          };

          devLocal = pkgs.writeShellApplication {
            name = "kanwas-dev-local";
            runtimeInputs = with pkgs; [
              corepack
              nodejs_24
              postgresql_17
              redis
              initLocal
            ];
            text = ''
              set -euo pipefail

              export KANWAS_NIX_DATA_DIR="''${KANWAS_NIX_DATA_DIR:-$PWD/.nix-data}"
              export PGDATA="''${PGDATA:-$KANWAS_NIX_DATA_DIR/postgres}"
              export PGHOST="''${PGHOST:-127.0.0.1}"
              export PGPORT="''${PGPORT:-5432}"
              export PGUSER="''${PGUSER:-kanwas}"
              export PGDATABASE="''${PGDATABASE:-kanwas}"

              backend_pid=""
              yjs_pid=""
              frontend_pid=""
              redis_pid=""

              cleanup() {
                for pid in "$backend_pid" "$yjs_pid" "$frontend_pid" "$redis_pid"; do
                  if [ -n "$pid" ]; then
                    kill "$pid" 2>/dev/null || true
                  fi
                done
                pg_ctl -D "$PGDATA" stop -m fast >/dev/null 2>&1 || true
              }
              trap cleanup EXIT INT TERM

              mkdir -p "$KANWAS_NIX_DATA_DIR" "$KANWAS_NIX_DATA_DIR/redis"
              kanwas-init-local
              corepack enable >/dev/null 2>&1 || true

              if [ ! -d "$PGDATA" ] || [ ! -s "$PGDATA/PG_VERSION" ]; then
                initdb -D "$PGDATA" --username=kanwas --auth=trust >/dev/null
              fi

              pg_socket_dir="$KANWAS_NIX_DATA_DIR/postgres-socket"
              mkdir -p "$pg_socket_dir"

              pg_ctl -D "$PGDATA" -l "$KANWAS_NIX_DATA_DIR/postgres.log" -o "-h $PGHOST -p $PGPORT -k $pg_socket_dir" start
              redis-server --dir "$KANWAS_NIX_DATA_DIR/redis" --port 6379 --save "" --appendonly no > "$KANWAS_NIX_DATA_DIR/redis.log" 2>&1 &
              redis_pid=$!

              until pg_isready -h "$PGHOST" -p "$PGPORT" -U kanwas >/dev/null 2>&1; do
                sleep 0.2
              done

              createdb -h "$PGHOST" -p "$PGPORT" -U kanwas kanwas >/dev/null 2>&1 || true

              pnpm install
              pnpm --filter shared build
              pnpm --filter backend migrate

              pnpm --filter backend dev &
              backend_pid=$!
              pnpm --filter kanwas-yjs-server dev &
              yjs_pid=$!
              pnpm --filter frontend dev -- --host 127.0.0.1 &
              frontend_pid=$!

              echo "Kanwas local stack started"
              echo "  frontend: http://127.0.0.1:5173"
              echo "  backend:  http://127.0.0.1:3333"
              echo "  yjs:      ws://127.0.0.1:1999"
              echo "Press Ctrl-C to stop all local services."

              wait -n "$backend_pid" "$yjs_pid" "$frontend_pid"
            '';
          };
        in
        {
          inherit initLocal devLocal;
          default = devLocal;
        });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.system}.devLocal}/bin/kanwas-dev-local";
        };
        init = {
          type = "app";
          program = "${self.packages.${pkgs.system}.initLocal}/bin/kanwas-init-local";
        };
      });
    };
}
