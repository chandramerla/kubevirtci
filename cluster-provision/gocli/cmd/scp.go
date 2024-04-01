package cmd

import (
	"context"
	"os"

	"github.com/docker/docker/client"
	"github.com/spf13/cobra"
	"kubevirt.io/kubevirtci/cluster-provision/gocli/cmd/utils"
	"kubevirt.io/kubevirtci/cluster-provision/gocli/docker"

	"bytes"
	"fmt"
	"io"
	"strconv"
	"strings"

	ssh1 "golang.org/x/crypto/ssh"
)

const sshKey = `-----BEGIN OPENSSH PRIVATE KEY-----
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
-----END OPENSSH PRIVATE KEY-----`

// NewSCPCommand returns command to copy files via SSH from the cluster node to localhost
func NewSCPCommand() *cobra.Command {

	ssh := &cobra.Command{
		Use:   "scp SRC DST",
		Short: "scp copies files from control-plane node to the local host",
		RunE:  scp,
		Args:  cobra.MinimumNArgs(2),
	}

	ssh.Flags().String("container-name", "dnsmasq", "the container name to SSH copy from")
	ssh.Flags().String("ssh-user", "cloud-user", "the user that used to connect via SSH to the node")

	return ssh
}

func scp(cmd *cobra.Command, args []string) error {

	prefix, err := cmd.Flags().GetString("prefix")
	if err != nil {
		return err
	}

	containerName, err := cmd.Flags().GetString("container-name")
	if err != nil {
		return err
	}

	sshUser, err := cmd.Flags().GetString("ssh-user")
	if err != nil {
		return err
	}

	src := args[0]
	dst := args[1]

	cli, err := client.NewEnvClient()
	if err != nil {
		return err
	}

	containers, err := docker.GetPrefixedContainers(cli, prefix+"-"+containerName)
	if err != nil {
		return err
	}

	if len(containers) != 1 {
		return fmt.Errorf("failed to found the container with name %s", prefix+"-"+containerName)
	}
	container, err := cli.ContainerInspect(context.Background(), containers[0].ID)
	if err != nil {
		return err
	}

	sshPort, err := utils.GetPublicPort(utils.PortSSH, container.NetworkSettings.Ports)
	if err != nil {
		return err
	}

	signer, err := ssh1.ParsePrivateKey([]byte(sshKey))
	if err != nil {
		return err
	}

	config := &ssh1.ClientConfig{
		User: sshUser,
		Auth: []ssh1.AuthMethod{
			ssh1.PublicKeys(signer),
		},
		HostKeyCallback: ssh1.InsecureIgnoreHostKey(),
	}

	connection, err := ssh1.Dial("tcp", fmt.Sprintf("127.0.0.1:%v", sshPort), config)
	if err != nil {
		return err
	}

	session, err := connection.NewSession()
	if err != nil {
		return err
	}
	defer session.Close()

	stdout, err := session.StdoutPipe()
	if err != nil {
		return fmt.Errorf("Unable to setup stdout for session: %v", err)
	}

	stderr, err := session.StderrPipe()
	if err != nil {
		return fmt.Errorf("Unable to setup stderr for session: %v", err)
	}
	go io.Copy(os.Stderr, stderr)

	var target *os.File
	if dst == "-" {
		target = os.Stdout
	} else {
		target, err = os.Create(dst)
		if err != nil {
			return err
		}
	}

	errChan := make(chan error)

	go func() {
		defer close(errChan)
		b := make([]byte, 1)
		var buf bytes.Buffer
		for {
			n, err := stdout.Read(b)
			if err != nil {
				errChan <- fmt.Errorf("error: %v", err)
				return
			}
			if n == 0 {
				continue
			}

			if b[0] == '\n' {
				break
			}
			buf.WriteByte(b[0])
		}

		metadata := strings.Split(buf.String(), " ")
		if len(metadata) < 3 || !strings.HasPrefix(buf.String(), "C") {
			errChan <- fmt.Errorf("%v", buf.String())
			return
		}
		l, err := strconv.Atoi(metadata[1])
		if err != nil {
			errChan <- fmt.Errorf("invalid metadata: %v", buf.String())
			return
		}
		_, err = io.CopyN(target, stdout, int64(l))
		errChan <- err
	}()
	wrPipe, err := session.StdinPipe()
	if err != nil {
		return fmt.Errorf("failed to open pipe: %v", err)
	}

	go func(wrPipe io.WriteCloser) {
		defer wrPipe.Close()
		fmt.Fprintf(wrPipe, "\x00")
		fmt.Fprintf(wrPipe, "\x00")
		fmt.Fprintf(wrPipe, "\x00")
		fmt.Fprintf(wrPipe, "\x00")
	}(wrPipe)

	err = session.Run("sudo -i /usr/bin/scp -qf " + src)

	copyError := <-errChan

	if err == nil && copyError != nil {
		return copyError
	}

	if copyError != nil {
		fmt.Fprintln(cmd.OutOrStderr(), copyError)
	}

	return err
}
