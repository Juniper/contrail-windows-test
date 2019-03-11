class MultiNode {
    [ContrailRestApi] $ContrailRestApi
    [VirtualRouter[]] $VRouters
    [Project] $Project

    MultiNode([ContrailRestApi] $ContrailRestApi,
        [VirtualRouter[]] $VRouters,
        [Project] $Project) {

        $this.ContrailRestApi = $ContrailRestApi
        $this.VRouters = $VRouters
        $this.Project = $Project
    }
}
