package main

import (
	"flag"
	"fmt"
	"html/template"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"os"
	"runtime"
	"sort"
	"strings"
	"syscall"
	"time"

	"github.com/bmatcuk/doublestar"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

var startTime time.Time

func uptime() time.Duration {
	return time.Since(startTime)
}

func init() {
	startTime = time.Now()
}

// see https://github.com/kubernetes/client-go/tree/v12.0.0/examples/in-cluster-client-configuration
// see https://github.com/kubernetes/client-go/blob/v12.0.0/kubernetes/typed/core/v1/pod.go
func getPodContainers() (string, error) {
	podNamespace := os.Getenv("POD_NAMESPACE")
	podName := os.Getenv("POD_NAME")
	config, err := rest.InClusterConfig()
	if err != nil {
		return "", err
	}
	client, err := kubernetes.NewForConfig(config)
	if err != nil {
		return "", err
	}
	pod, err := client.CoreV1().Pods(podNamespace).Get(podName, metav1.GetOptions{})
	if err != nil {
		return "", err
	}
	var b strings.Builder
	for _, container := range pod.Spec.Containers {
		fmt.Fprintf(&b, "%s %s\n", container.Name, container.Image)
	}
	return b.String(), nil
}

var indexTemplate = template.Must(template.New("Index").Parse(`<!DOCTYPE html>
<html>
<head>
<title>go-info</title>
<style>
body {
    font-family: monospace;
    color: #555;
    background: #e6edf4;
    padding: 1.25rem;
    margin: 0;
}
table {
    background: #fff;
    border: .0625rem solid #c4cdda;
    border-radius: 0 0 .25rem .25rem;
    border-spacing: 0;
    margin-bottom: 1.25rem;
    padding: .75rem 1.25rem;
    text-align: left;
    white-space: pre;
}
table > caption {
    background: #f1f6fb;
    text-align: left;
    font-weight: bold;
    padding: .75rem 1.25rem;
    border: .0625rem solid #c4cdda;
    border-radius: .25rem .25rem 0 0;
    border-bottom: 0;
}
table td, table th {
    padding: .25rem;
}
table > tbody > tr:hover {
    background: #f1f6fb;
}
</style>
</head>
<body>
    <table>
        <caption>Properties</caption>
        <tbody>
            <tr><th>Pid</th><td>{{.Pid}}</td></tr>
            <tr><th>Uid</th><td>{{.Uid}}</td></tr>
            <tr><th>Gid</th><td>{{.Gid}}</td></tr>
            <tr><th>Request</th><td>{{.Request}}</td></tr>
            <tr><th>Client Address</th><td>{{.ClientAddress}}</td></tr>
            <tr><th>Server Address</th><td>{{.ServerAddress}}</td></tr>
            <tr><th>Hostname</th><td>{{.Hostname}}</td></tr>
            <tr><th>Pod Containers</th><td>{{.PodContainers}}</td></tr>
            <tr><th>Cgroup</th><td>{{.Cgroup}}</td></tr>
            <tr><th>Memory Limit</th><td>{{.MemoryLimit}}</td></tr>
            <tr><th>Memory Usage</th><td>{{.MemoryUsage}}</td></tr>
            <tr><th>Os</th><td>{{.Os}}</td></tr>
            <tr><th>Architecture</th><td>{{.Architecture}}</td></tr>
            <tr><th>Runtime</th><td>{{.Runtime}}</td></tr>
            <tr><th>Uptime</th><td>{{.Uptime}}</td></tr>
        </tbody>
    </table>
    <table>
        <caption>Environment Variables</caption>
        <tbody>
            {{- range .Environment}}
            <tr>
                <th>{{.Name}}</th>
                <td>{{.Value}}</td>
            </tr>
            {{- end}}
        </tbody>
    </table>
    <table>
        <caption>Secrets</caption>
        <tbody>
            {{- range .Secrets}}
            <tr>
                <th>{{.Name}}</th>
                <td>{{.Value}}</td>
            </tr>
            {{- end}}
        </tbody>
    </table>
    <table>
        <caption>Configs</caption>
        <tbody>
            {{- range .Configs}}
            <tr>
                <th>{{.Name}}</th>
                <td>{{.Value}}</td>
            </tr>
            {{- end}}
        </tbody>
    </table>
</body>
</html>
`))

type nameValuePair struct {
	Name  string
	Value string
}

type indexData struct {
	Pid           int
	Uid           int
	Gid           int
	PodContainers string
	Cgroup        string
	MemoryLimit   string
	MemoryUsage   string
	Request       string
	ClientAddress string
	ServerAddress string
	Hostname      string
	Os            string
	Architecture  string
	Runtime       string
	Uptime        string
	Environment   []nameValuePair
	Secrets       []nameValuePair
	Configs       []nameValuePair
}

type nameValuePairs []nameValuePair

func (a nameValuePairs) Len() int           { return len(a) }
func (a nameValuePairs) Swap(i, j int)      { a[i], a[j] = a[j], a[i] }
func (a nameValuePairs) Less(i, j int) bool { return a[i].Name < a[j].Name }

func main() {
	log.SetFlags(0)

	var listenAddress = flag.String("listen", ":8000", "Listen address.")

	flag.Parse()

	if flag.NArg() != 0 {
		flag.Usage()
		log.Fatalf("\nERROR You MUST NOT pass any positional arguments")
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Printf("%s %s%s\n", r.Method, r.Host, r.URL)

		if r.URL.Path != "/" {
			http.Error(w, "Not Found", http.StatusNotFound)
			return
		}

		hostname, err := os.Hostname()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "text/html")

		environment := make([]nameValuePair, 0)
		for _, v := range os.Environ() {
			parts := strings.SplitN(v, "=", 2)
			name := parts[0]
			value := parts[1]
			switch name {
			case "PATH":
				fallthrough
			case "XDG_DATA_DIRS":
				fallthrough
			case "XDG_CONFIG_DIRS":
				value = strings.Join(
					strings.Split(value, string(os.PathListSeparator)),
					"\n")
			}
			environment = append(environment, nameValuePair{name, value})
		}
		sort.Sort(nameValuePairs(environment))

		secrets := make([]nameValuePair, 0)
		secretFiles, _ := doublestar.Glob("/var/run/secrets/**")
		for _, v := range secretFiles {
			if strings.Contains(v, "/.") {
				continue
			}
			fi, err := os.Stat(v)
			if err != nil {
				log.Fatal(err)
			}
			mode := fi.Mode()
			if !mode.IsRegular() {
				continue
			}
			uid := fi.Sys().(*syscall.Stat_t).Uid
			gid := fi.Sys().(*syscall.Stat_t).Gid
			name := v[len("/var/run/secrets/"):]
			value, _ := ioutil.ReadFile(v)
			secrets = append(secrets, nameValuePair{fmt.Sprintf("%s %d %d %s", mode, uid, gid, name), string(value)})
		}
		sort.Sort(nameValuePairs(secrets))

		configs := make([]nameValuePair, 0)
		configFiles, _ := doublestar.Glob("/var/run/configs/**")
		for _, v := range configFiles {
			if strings.Contains(v, "/.") {
				continue
			}
			fi, err := os.Stat(v)
			if err != nil {
				log.Fatal(err)
			}
			mode := fi.Mode()
			if !mode.IsRegular() {
				continue
			}
			uid := fi.Sys().(*syscall.Stat_t).Uid
			gid := fi.Sys().(*syscall.Stat_t).Gid
			name := v[len("/var/run/configs/"):]
			value, _ := ioutil.ReadFile(v)
			configs = append(configs, nameValuePair{fmt.Sprintf("%s %d %d %s", mode, uid, gid, name), string(value)})
		}
		sort.Sort(nameValuePairs(configs))

		cgroup, err := ioutil.ReadFile("/proc/self/cgroup")
		if err != nil {
			panic(err)
		}

		memoryLimit, err := ioutil.ReadFile("/sys/fs/cgroup/memory/memory.limit_in_bytes")
		if err != nil {
			panic(err)
		}

		memoryUsage, err := ioutil.ReadFile("/sys/fs/cgroup/memory/memory.usage_in_bytes")
		if err != nil {
			panic(err)
		}

		podContainers, err := getPodContainers()
		if err != nil {
			panic(err)
		}

		err = indexTemplate.ExecuteTemplate(w, "Index", indexData{
			Pid:           os.Getpid(),
			Uid:           os.Getuid(),
			Gid:           os.Getgid(),
			PodContainers: podContainers,
			Cgroup:        string(cgroup),
			MemoryLimit:   string(memoryLimit),
			MemoryUsage:   string(memoryUsage),
			Request:       fmt.Sprintf("%s %s%s", r.Method, r.Host, r.URL),
			ClientAddress: r.RemoteAddr,
			ServerAddress: r.Context().Value(http.LocalAddrContextKey).(net.Addr).String(),
			Hostname:      hostname,
			Os:            runtime.GOOS,
			Architecture:  runtime.GOARCH,
			Runtime:       runtime.Version(),
			Uptime:        uptime().String(),
			Environment:   environment,
			Secrets:       secrets,
			Configs:       configs,
		})
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
	})

	fmt.Printf("Listening at http://%s\n", *listenAddress)

	err := http.ListenAndServe(*listenAddress, nil)
	if err != nil {
		log.Fatalf("Failed to ListenAndServe: %v", err)
	}
}
