#!/usr/bin/env python3
"""Run any scenario with one short command. Needs only Python 3 (no packages) and bash.

    python3 z2h.py list                  all Kubernetes scenarios, by section
    python3 z2h.py list docker           the Docker scenarios
    python3 z2h.py break  S1.2           set the scene (same as: cd break && ./break.sh)
    python3 z2h.py check  S1.2           "am I done?"  (read-only)
    python3 z2h.py fix    S1.2           apply the fix
    python3 z2h.py cleanup S1.2          remove everything the scenario created
    python3 z2h.py test   S1.2           run the automated break/fix test (throwaway cluster only)
    python3 z2h.py open   S1.2           open the app in your browser (kubectl port-forward on a free port)
    python3 z2h.py open   S1.2 --port 9000  choose the port on your laptop yourself
    python3 z2h.py open   S1.2 --public  same, but on all interfaces (Killercoda, iximiuz)
    python3 z2h.py open   S1.2 --nodeport  switch its Service to NodePort and print the port (Killercoda, iximiuz)
    python3 z2h.py open                  list the scenarios that have a page

Ids: S1.2 = Kubernetes section 1, scenario 2 (S1.x1 = exercise 1). D02 = Docker scenario 2.
Kubernetes break, fix and cleanup are Python (they run kubectl for you). check.sh and the
Docker scripts are bash; on Windows use Git Bash or WSL for those.
This file only finds the right script and runs it, so you never have to remember a folder path.
"""
import csv
import os
import shutil
import socket
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
K8S = os.path.join(ROOT, "kubernetes", "scenarios")
DOCKER = os.path.join(ROOT, "docker", "scenarios")

# action -> the scripts to try, in order (the Python one first; bash is the fallback)
SCRIPTS = {
    "break": ("break/run.py", "break/break.sh"),
    "fix": ("fix/run.py", "fix/fix.sh"),
    "check": ("check.sh",),
    "cleanup": ("cleanup.py", "cleanup.sh"),
}


def find_bash():
    bash = shutil.which("bash")
    if not bash:
        sys.exit("bash was not found. On Windows, open Git Bash (or WSL) and run this again.")
    return bash


def k8s_rows():
    """Every Kubernetes scenario: (id, folder, kind, title), read from index.tsv."""
    with open(os.path.join(K8S, "index.tsv"), encoding="utf-8", newline="") as f:
        reader = csv.reader(f, delimiter="\t")
        next(reader)  # header
        return [(r[0], os.path.join(K8S, r[2]), r[3], r[4]) for r in reader]


def docker_rows():
    rows = []
    for name in sorted(os.listdir(DOCKER)):
        path = os.path.join(DOCKER, name)
        if os.path.isdir(path) and name[:2].isdigit():
            title = name[3:].replace("-", " ")
            try:
                with open(os.path.join(path, "README.md"), encoding="utf-8") as f:
                    title = f.readline().lstrip("# ").strip()
                    title = title.split("·", 1)[-1].strip()
            except OSError:
                pass
            rows.append(("D" + name[:2], path, "core", title))
    return rows


def find(scenario_id):
    """Turn what the user typed (S2.3, 2.3, s2.3, D02, 2) into (id, folder, kind)."""
    wanted = scenario_id.strip().upper()
    if wanted.isdigit() and len(wanted) <= 2:
        wanted = "D" + wanted.zfill(2)
    elif wanted[:1].isdigit():
        wanted = "S" + wanted
    for sid, folder, kind, _title in k8s_rows() + docker_rows():
        if sid.upper() == wanted:
            return sid, folder, kind
    sys.exit("No scenario called '%s'. Try:  python3 z2h.py list" % scenario_id)


def show_list(which):
    if which == "docker":
        for sid, _folder, _kind, title in docker_rows():
            print("  %-4s %s" % (sid, title))
        return
    section = ""
    for sid, folder, kind, title in k8s_rows():
        head = os.path.relpath(folder, K8S).split(os.sep)[0]
        if head != section:
            section = head
            num, _, name = section.partition("-")
            print("\nSection %s: %s" % (num, name.replace("-", " ")))
        label = "  (exercise)" if "exercises" in folder else ""
        print("  %-7s %s%s" % (sid, title, label))


def web_rows():
    """Scenarios with a web page: {id: (namespace, service)}, from web.tsv."""
    rows = {}
    with open(os.path.join(K8S, "web.tsv"), encoding="utf-8", newline="") as f:
        reader = csv.reader(f, delimiter="\t")
        next(reader)
        for sid, namespace, service in reader:
            rows[sid.upper()] = (namespace, service)
    return rows


def kubectl_text(*args):
    done = subprocess.run(["kubectl", *args], capture_output=True, text=True, encoding="utf-8", errors="replace")
    return done.returncode, done.stdout.strip()


def free_port(start=8888):
    """The first port from `start` upwards that nothing on this computer is listening on."""
    for port in range(start, start + 100):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            probe.settimeout(0.5)
            if probe.connect_ex(("127.0.0.1", port)) != 0:
                return port
    sys.exit("Could not find a free port near %d. Close something, or choose one with --port." % start)


def open_app(args):
    """Open a scenario's page: port-forward by default, NodePort on request."""
    flags = [a for a in args if a.startswith("--")]
    plain = [a for a in args if not a.startswith("--")]
    wanted_port = None
    if "--port" in args:                      # --port 9000 (the number follows the flag)
        at = args.index("--port")
        if at + 1 >= len(args) or not args[at + 1].isdigit():
            sys.exit("--port needs a number, for example:  python3 z2h.py open S1.2 --port 9000")
        wanted_port = int(args[at + 1])
        plain = [a for a in plain if a != args[at + 1]]
    web = web_rows()
    if not plain:
        print("Scenarios with a page (python3 z2h.py open <id>):")
        for sid in web:
            print("  %-7s %s" % (sid, web[sid][1]))
        return 0
    sid = find(plain[0])[0].upper()
    if sid not in web:
        sys.exit("%s has no web page: check it in the terminal (see its README)." % sid)
    namespace, service = web[sid]
    code, service_port = kubectl_text("get", "svc", service, "-n", namespace, "-o", "jsonpath={.spec.ports[0].port}")
    if code != 0:
        sys.exit("The Service %s/%s is not there yet. Set the scene first:  python3 z2h.py break %s" % (namespace, service, sid))
    if "--nodeport" in flags:
        kubectl_text("patch", "svc", service, "-n", namespace, "-p", '{"spec":{"type":"NodePort"}}')
        _, node_port = kubectl_text("get", "svc", service, "-n", namespace, "-o", "jsonpath={.spec.ports[0].nodePort}")
        _, node_ip = kubectl_text("get", "nodes", "-o",
                                  'jsonpath={.items[0].status.addresses[?(@.type=="InternalIP")].address}')
        print("The Service %s is now a NodePort: %s" % (service, node_port or "(could not read it)"))
        print("  In a Killercoda or iximiuz terminal:  curl http://%s:%s" % (node_ip or "<node-ip>", node_port or "<nodeport>"))
        print("  In the browser: open the platform's Traffic / Ports menu and enter %s" % (node_port or "the NodePort"))
        print("  On kind, minikube or Docker Desktop this address is not your laptop: use port-forward instead.")
        return 0
    port = wanted_port or free_port()
    command = ["kubectl", "port-forward", "-n", namespace, "svc/" + service, "%d:%s" % (port, service_port or "80")]
    if "--public" in flags:
        command[2:2] = ["--address", "0.0.0.0"]
        print("Listening on ALL interfaces: anyone on this network can open the app. Ctrl+C when you are done.")
        print("On Killercoda or iximiuz open the platform's port link for %d." % port)
    else:
        print("Open  http://localhost:%d   (Ctrl+C to stop)" % port)
    print("Running: " + " ".join(command))
    try:
        return subprocess.call(command)
    except KeyboardInterrupt:
        return 0


def run(action, scenario_id):
    sid, folder, kind = find(scenario_id)
    if kind == "question" and action != "cleanup":
        sys.exit("%s is a question exercise: there is no script to run.\nOpen %s and follow the steps."
                 % (sid, os.path.join(folder, "README.md")))
    for name in SCRIPTS[action]:
        path = os.path.join(folder, *name.split("/"))
        if os.path.exists(path):
            break
    else:
        sys.exit("%s has no %s script." % (sid, action))
    # Like the README says: break runs from break/, fix from fix/.
    runner = [sys.executable] if path.endswith(".py") else [find_bash()]
    return subprocess.call(runner + [path], cwd=os.path.dirname(path))


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help", "help"):
        print(__doc__)
        return 0
    action = argv[1]
    if action == "open":
        return open_app(argv[2:])
    if action == "list":
        show_list(argv[2] if len(argv) > 2 else "k8s")
        return 0
    if len(argv) < 3:
        sys.exit("Which scenario? Example:  python3 z2h.py %s S1.2" % action)
    if action == "test":
        sid, _folder, _kind = find(argv[2])
        return subprocess.call([find_bash(), os.path.join(ROOT, "tests", "scenarios", "k8s.sh"), sid])
    if action in SCRIPTS:
        return run(action, argv[2])
    sys.exit("Unknown command '%s'. Run:  python3 z2h.py help" % action)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
