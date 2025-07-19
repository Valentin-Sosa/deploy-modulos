#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/AlvaroGianola/tp-2025-1c-LaBestiaDeCalchin.git"
USER="AlvaroGianola"

# Variables globales para re-ejecución
MODULE=""
ARGS=()
CONFIG_FILE=""
RUNNING=0

# ---------- Utilidades ----------
ask() {
  local prompt="$1"; shift
  local default="${1:-}"
  local var
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " var || true
    [[ -z "$var" ]] && var="$default"
  else
    read -r -p "$prompt: " var || true
    while [[ -z "$var" ]]; do
      read -r -p "(Obligatorio) $prompt: " var || true
    done
  fi
  echo "$var"
}

detect_ip() {
  local ip
  ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}') || true
  [[ -z "$ip" ]] && ip=$(hostname -I 2>/dev/null | awk '{print $1}') || true
  [[ -z "$ip" ]] && ip=$(ip -4 addr show | awk '/inet / {gsub(/\/.*/,"",$2); if($2!~/^127\./){print $2; exit}}') || true
  [[ -z "$ip" ]] && ip="127.0.0.1"
  echo "$ip"
}

need_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "[ERROR] Se requiere 'jq' para edición parcial. Instalalo con: sudo apt install -y jq"
    return 1
  fi
  return 0
}

press_enter() {
  read -rp "Presioná ENTER para continuar..." _ || true
}

# ---------- Construcción de config completa ----------
full_config_kernel() {
  local ip_vm="$1"
  local ip_memory port_kernel port_memory scheduler ready_alg alpha init_est suspension log_level
  ip_memory=$(ask "IP Memoria" "$ip_vm")
  port_kernel=$(ask "Puerto Kernel" "8001")
  port_memory=$(ask "Puerto Memoria" "8002")
  scheduler=$(ask "Algoritmo corto plazo (FIFO/SJF/SRT)" "SRT")
  ready_alg=$(ask "Algoritmo READY ingreso (FIFO/PMCP)" "PMCP")
  alpha=$(ask "Alpha" "0.75")
  init_est=$(ask "Estimación inicial (ms)" "100")
  suspension=$(ask "Suspensión (ms)" "3000")
  log_level=$(ask "Log level" "INFO")
  cat > "$CONFIG_FILE" <<EOF
{
  "ip_memory": "$ip_memory",
  "port_memory": $port_memory,
  "ip_kernel": "$ip_vm",
  "port_kernel": $port_kernel,
  "scheduler_algorithm": "$scheduler",
  "ready_ingress_algorithm": "$ready_alg",
  "alpha": $alpha,
  "initial_estimate": $init_est,
  "suspension_time": $suspension,
  "log_level": "$log_level"
}
EOF
}

full_config_cpu() {
  local ip_vm="$1"
  local ip_kernel ip_memory port_cpu port_kernel port_memory tlb_entries tlb_replacement cache_entries cache_replacement cache_delay log_level
  ip_kernel=$(ask "IP Kernel" "$ip_vm")
  ip_memory=$(ask "IP Memoria" "$ip_vm")
  port_cpu=$(ask "Puerto CPU" "8004")
  port_kernel=$(ask "Puerto Kernel" "8001")
  port_memory=$(ask "Puerto Memoria" "8002")
  tlb_entries=$(ask "Entradas TLB" "4")
  tlb_replacement=$(ask "Algoritmo TLB (FIFO/LRU)" "FIFO")
  cache_entries=$(ask "Entradas Cache" "2")
  cache_replacement=$(ask "Algoritmo Cache (CLOCK/CLOCK-M)" "CLOCK")
  cache_delay=$(ask "Delay Cache (ms)" "50")
  log_level=$(ask "Log level" "INFO")
  cat > "$CONFIG_FILE" <<EOF
{
  "port_cpu": $port_cpu,
  "ip_cpu": "$ip_vm",
  "ip_memory": "$ip_memory",
  "port_memory": $port_memory,
  "ip_kernel": "$ip_kernel",
  "port_kernel": $port_kernel,
  "tlb_entries": $tlb_entries,
  "tlb_replacement": "$tlb_replacement",
  "cache_entries": $cache_entries,
  "cache_replacement": "$cache_replacement",
  "cache_delay": $cache_delay,
  "log_level": "$log_level"
}
EOF
}

full_config_io() {
  local ip_vm="$1"
  local ip_kernel port_io port_kernel log_level
  ip_kernel=$(ask "IP Kernel" "$ip_vm")
  port_io=$(ask "Puerto IO" "8003")
  port_kernel=$(ask "Puerto Kernel" "8001")
  log_level=$(ask "Log level" "INFO")
  cat > "$CONFIG_FILE" <<EOF
{
  "ip_kernel": "$ip_kernel",
  "port_kernel": $port_kernel,
  "port_io": $port_io,
  "ip_io": "$ip_vm",
  "log_level": "$log_level"
}
EOF
}

full_config_memoria() {
  local ip_vm="$1"
  local port_memory memory_size page_size log_level
  port_memory=$(ask "Puerto Memoria" "8002")
  memory_size=$(ask "Tamaño memoria (bytes)" "4096")
  page_size=$(ask "Tamaño página (bytes)" "64")
  log_level=$(ask "Log level" "INFO")
  cat > "$CONFIG_FILE" <<EOF
{
  "port_memory": $port_memory,
  "ip_memory": "$ip_vm",
  "memory_size": $memory_size,
  "page_size": $page_size,
  "log_level": "$log_level"
}
EOF
}

build_full_config() {
  local ip_vm
  ip_vm=$(detect_ip)
  echo "IP detectada: $ip_vm"
  echo "[Generando configuración completa: $CONFIG_FILE]"
  case "$MODULE" in
    kernel)  full_config_kernel "$ip_vm" ;;
    cpu)     full_config_cpu "$ip_vm" ;;
    io)      full_config_io "$ip_vm" ;;
    memoria) full_config_memoria "$ip_vm" ;;
  esac
  echo "[OK] Configuración escrita."
}

# ---------- Menús de edición ----------
edit_menu_kernel() {
  need_jq || return 1
  while true; do
    echo "Campos Kernel para editar:"
    echo " 1) ip_memory"
    echo " 2) port_memory"
    echo " 3) scheduler_algorithm"
    echo " 4) ready_ingress_algorithm"
    echo " 5) alpha"
    echo " 6) initial_estimate"
    echo " 7) suspension_time"
    echo " 8) log_level"
    echo " 9) Volver / terminar edición"
    read -r -p "Opción: " op
    case "$op" in
      1) v=$(ask "Nuevo ip_memory"); jq ".ip_memory = \"$v\"" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      2) v=$(ask "Nuevo port_memory"); jq ".port_memory = $v" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      3) v=$(ask "Nuevo scheduler_algorithm"); jq ".scheduler_algorithm = \"$v\"" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      4) v=$(ask "Nuevo ready_ingress_algorithm"); jq ".ready_ingress_algorithm = \"$v\"" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      5) v=$(ask "Nuevo alpha"); jq ".alpha = $v" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      6) v=$(ask "Nueva initial_estimate"); jq ".initial_estimate = $v" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      7) v=$(ask "Nueva suspension_time"); jq ".suspension_time = $v" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      8) v=$(ask "Nuevo log_level"); jq ".log_level = \"$v\"" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      9) break ;;
      *) echo "Opción inválida";;
    esac
    echo "[OK] Actualizado."
  done
}

edit_menu_cpu() {
  need_jq || return 1
  while true; do
    echo "Campos CPU para editar:"
    echo " 1) ip_cpu (auto = IP VM actual)"
    echo " 2) ip_kernel"
    echo " 3) ip_memory"
    echo " 4) port_cpu"
    echo " 5) port_kernel"
    echo " 6) port_memory"
    echo " 7) tlb_entries"
    echo " 8) tlb_replacement"
    echo " 9) cache_entries"
    echo "10) cache_replacement"
    echo "11) cache_delay"
    echo "12) log_level"
    echo "13) Volver"
    read -r -p "Opción: " op
    case "$op" in
      1) v=$(detect_ip); echo "Usando IP vm: $v"; jq ".ip_cpu = \"$v\"" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      2) v=$(ask "Nuevo ip_kernel"); jq ".ip_kernel = \"$v\"" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      3) v=$(ask "Nuevo ip_memory"); jq ".ip_memory = \"$v\"" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      4) v=$(ask "Nuevo port_cpu"); jq ".port_cpu = $v" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      5) v=$(ask "Nuevo port_kernel"); jq ".port_kernel = $v" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      6) v=$(ask "Nuevo port_memory"); jq ".port_memory = $v" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      7) v=$(ask "Nuevo tlb_entries"); jq ".tlb_entries = $v" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      8) v=$(ask "Nuevo tlb_replacement"); jq ".tlb_replacement = \"$v\"" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      9) v=$(ask "Nuevo cache_entries"); jq ".cache_entries = $v" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      10) v=$(ask "Nuevo cache_replacement"); jq ".cache_replacement = \"$v\"" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      11) v=$(ask "Nuevo cache_delay"); jq ".cache_delay = $v" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      12) v=$(ask "Nuevo log_level"); jq ".log_level = \"$v\"" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      13) break ;;
      *) echo "Opción inválida";;
    esac
    echo "[OK] Actualizado."
  done
}

edit_menu_io() {
  need_jq || return 1
  while true; do
    echo "Campos IO para editar:"
    echo " 1) ip_io (auto = IP VM actual)"
    echo " 2) ip_kernel"
    echo " 3) port_io"
    echo " 4) port_kernel"
    echo " 5) log_level"
    echo " 6) Volver"
    read -r -p "Opción: " op
    case "$op" in
      1) v=$(detect_ip); jq ".ip_io = \"$v\"" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      2) v=$(ask "Nuevo ip_kernel"); jq ".ip_kernel = \"$v\"" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      3) v=$(ask "Nuevo port_io"); jq ".port_io = $v" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      4) v=$(ask "Nuevo port_kernel"); jq ".port_kernel = $v" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      5) v=$(ask "Nuevo log_level"); jq ".log_level = \"$v\"" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      6) break ;;
      *) echo "Opción inválida";;
    esac
    echo "[OK] Actualizado."
  done
}

edit_menu_memoria() {
  need_jq || return 1
  while true; do
    echo "Campos Memoria para editar:"
    echo " 1) ip_memory (auto = IP VM actual)"
    echo " 2) port_memory"
    echo " 3) memory_size"
    echo " 4) page_size"
    echo " 5) log_level"
    echo " 6) Volver"
    read -r -p "Opción: " op
    case "$op" in
      1) v=$(detect_ip); jq ".ip_memory = \"$v\"" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      2) v=$(ask "Nuevo port_memory"); jq ".port_memory = $v" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      3) v=$(ask "Nuevo memory_size"); jq ".memory_size = $v" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      4) v=$(ask "Nuevo page_size"); jq ".page_size = $v" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      5) v=$(ask "Nuevo log_level"); jq ".log_level = \"$v\"" "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE" ;;
      6) break ;;
      *) echo "Opción inválida";;
    esac
    echo "[OK] Actualizado."
  done
}

edit_partial_config() {
  echo "[Edición parcial de $CONFIG_FILE]"
  case "$MODULE" in
    kernel)  edit_menu_kernel ;;
    cpu)     edit_menu_cpu ;;
    io)      edit_menu_io ;;
    memoria) edit_menu_memoria ;;
  esac
}

# ---------- Ejecución del módulo ----------
gather_runtime_args() {
  ARGS=()
  case "$MODULE" in
    kernel)
      local archivo tam
      archivo=$(ask "Archivo pseudocódigo" "./scripts/proceso1.txt")
      tam=$(ask "Tamaño proceso (bytes)" "256")
      ARGS=("$archivo" "$tam")
      ;;
    cpu)
      local ident
      ident=$(ask "Identificador CPU" "cpu1")
      ARGS=("$ident")
      ;;
    io)
      local nombre
      nombre=$(ask "Nombre dispositivo IO" "io1")
      ARGS=("$nombre")
      ;;
    memoria)
      ARGS=() # sin args
      ;;
  esac
}

run_module() {
  pushd "$MODULE" >/dev/null
  
echo "Instalando Go versión 1.22.3..."
wget https://go.dev/dl/go1.22.3.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.22.3.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

  echo "Compilando $MODULE..."
  go build -o "$MODULE" .
  echo "Ejecutando $MODULE ${ARGS[*]}"
  RUNNING=1
  # Trap dentro del contexto de ejecución
  ./"$MODULE" "${ARGS[@]}"
  RUNNING=0
  popd >/dev/null
}

# ---------- Ctrl + C ----------
ctrl_c_handler() {
  if [[ $RUNNING -eq 1 ]]; then
    echo -e "\n[Interrumpido - Ctrl + C]"
    read -r -p "¿Querés relanzar el módulo? (s/n): " r
    if [[ "$r" =~ ^[sS]$ ]]; then
      read -r -p "¿Configuración completa (t) o cambiar campos (c)? (t/c): " modo
      if [[ "$modo" =~ ^[tT]$ ]]; then
        build_full_config
        gather_runtime_args
      else
        if [[ ! -f "$CONFIG_FILE" ]]; then
          echo "[WARN] No existe config previa. Generando completa..."
          build_full_config
        else
          edit_partial_config
          # Preguntar si querés también cambiar argumentos de ejecución (para kernel/cpu/io)
          if [[ "$MODULE" != "memoria" ]]; then
            read -r -p "¿Cambiar también los argumentos de ejecución? (s/n): " ca
            if [[ "$ca" =~ ^[sS]$ ]]; then
              gather_runtime_args
            fi
          fi
        fi
      fi
      echo "Re-lanzando $MODULE..."
      run_module
    else
      echo "Saliendo."
      exit 0
    fi
  else
    echo "Interrupción fuera de ejecución principal. Saliendo."
    exit 0
  fi
}

trap ctrl_c_handler SIGINT

# ---------- Main ----------
main() {
    ip_vm=$(detect_ip)
  echo "IP detectada: $ip_vm"
  MODULE=$(ask "¿Qué módulo querés levantar? (kernel/cpu/io/memoria)" "kernel")
  MODULE=$(echo "$MODULE" | tr '[:upper:]' '[:lower:]')
  case "$MODULE" in
    kernel|cpu|io|memoria) ;;
    *) echo "Módulo inválido."; exit 1 ;;
  esac

  # Clonar repo si no está
  if [[ ! -d tp-2025-1c-LaBestiaDeCalchin ]]; then
    echo "Clonando repositorio..."
    git clone --depth=1 "$REPO_URL"
  else
    echo "Repositorio ya existe. Actualizando..."
    (cd tp-2025-1c-LaBestiaDeCalchin && git pull --ff-only || echo "[WARN] git pull falló, continuando...")
  fi

  cd tp-2025-1c-LaBestiaDeCalchin

  if [[ ! -d "$MODULE" ]]; then
    echo "[ERROR] No existe el directorio '$MODULE' dentro del repo."
    exit 1
  fi

  CONFIG_FILE="$MODULE/config.json"
  build_full_config
  gather_runtime_args
  run_module
}

main

