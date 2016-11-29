;;; Copyright (c) 2016, Jan Winkler <winkler@cs.uni-bremen.de>
;;; All rights reserved.
;;; 
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions are met:
;;; 
;;; * Redistributions of source code must retain the above copyright
;;;   notice, this list of conditions and the following disclaimer.
;;; * Redistributions in binary form must reproduce the above copyright
;;;   notice, this list of conditions and the following disclaimer in the
;;;   documentation and/or other materials provided with the distribution.
;;; 
;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
;;; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
;;; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;;; ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
;;; LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
;;; CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
;;; SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;;; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
;;; CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
;;; ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
;;; POSSIBILITY OF SUCH DAMAGE.

(in-package :ltfnp-executive)


;;;
;;; Auxiliary Functions
;;;

(defun do-init (simulated &key headless variance)
  (setf *simulated* simulated)
  (cond (*simulated*
         (setf cram-beliefstate::*kinect-topic-rgb* "/head_mount_kinect/rgb/image_raw");;/compressed")
         (setf pr2-manip-pm::*grasp-offset*
               (cl-transforms:make-pose
                (cl-transforms:make-3d-vector -0.14 0.0 0.0)
                (cl-transforms:euler->quaternion :ax (/ pi -2)))))
        (t (setf cram-moveit::*needs-ft-fix* t)
           (setf cram-beliefstate::*kinect-topic-rgb* "/kinect_head/rgb/image_color")))
  (roslisp:ros-info (ltfnp) "Connecting to ROS")
  (roslisp-utilities:startup-ros)
  (prepare-settings :simulated simulated :headless headless :variance variance)
  (roslisp:ros-info (ltfnp) "Putting the PR2 into defined start state")
  (move-arms-up)
  (move-torso))


;;;
;;; Entry Point
;;;

(defun start-scenario (&key (simulated t) (logged nil) skip-init headless (variance "{}"))
  ;; This function is mainly meant as an entry point for external
  ;; runner scripts (for starting the scenario using launch files,
  ;; etc.)
  (let ((variance (yason:parse variance)))
    (beliefstate:enable-logging nil)
    (unless skip-init
      (do-init simulated :headless headless :variance variance))
    (roslisp:ros-info (ltfnp) "Running Longterm Fetch and Place")
    (roslisp:ros-info (ltfnp) "Using variance: ~a" variance)
    (beliefstate:enable-logging logged)
    (setf beliefstate::*enable-prolog-logging* logged)
    (prog1
        (longterm-fetch-and-place :variance variance)
      (when logged
        (beliefstate:extract-files))
      (roslisp:ros-info (ltfnp) "Done with LTFnP"))))


;;;
;;; Top-Level Plans
;;;

(def-top-level-cram-function longterm-fetch-and-place (&key variance)
  (roslisp:ros-info (ltfnp) "Preparation complete, beginning actual scenario")
  (cond (*simulated*
         (roslisp:ros-info (ltfnp) "Environment: Simulated")
         (with-process-modules-simulated
           (fetch-and-place-instance :variance variance)))
        (t
         (roslisp:ros-info (ltfnp) "Environment: Real-World")
         (with-process-modules
           (fetch-and-place-instance :variance variance)))))

(defun make-object-location-goal (name &rest objects+locations)
  (make-instance
   'goal
   :name name
   :preconditions
   (mapcar (lambda (object+location)
             (destructuring-bind (object location) object+location
               `(:object-location ,(make-designator
                                    :object
                                    (enrich-description object))
                                  ,location)))
           objects+locations)))

(defun merge-goals (&rest rest)
  (let* ((names (loop for goal in rest
                      as name = (slot-value goal 'name)
                      collect name))
         (preconditions
           (loop for goal in rest
                 as precondition = (slot-value goal 'preconditions)
                 append precondition))
         (all-merged (reduce (lambda (s0 s1)
                               (concatenate 'string s0 "," s1))
                             names))
         (merged-name
           (concatenate 'string "merged(" all-merged ")")))
    (make-instance
     'goal
     :name merged-name
     :preconditions preconditions)))

(def-cram-function fetch-and-place-instance (&key variance)
  ;; TODO(winkler): Use the variance here to parameterize the
  ;; scenario.
  (let* ((target-table "iai_kitchen_meal_table_counter_top")
         (goal
           (merge-goals
            ;; (make-object-location-goal
            ;;  "fetch-fork"
            ;;  `(((:name "Fork")
            ;;     (:at ,(make-designator
            ;;            :location
            ;;            `((:in "Drawer")
            ;;              (:name "iai_kitchen_sink_area_left_upper_drawer_main")
            ;;              (:handle
            ;;               ,(make-designator
            ;;                 :object
            ;;                 `((:name "drawer_sinkblock_upper_handle")))))))
            ;;     (:location "drawer_sinkblock_upper"))
            ;;    ,(make-designator
            ;;      :location
            ;;      `((:on "CounterTop")
            ;;        (:name "iai_kitchen_meal_table_counter_top")))))
            
            ;; (make-fixed-tabletop-goal
            ;;  `(("RedMetalPlate" ,(tf:make-pose-stamped
            ;;                       "map" 0.0
            ;;                       (tf:make-3d-vector -1.35 -0.90 0.75)
            ;;                       (tf:euler->quaternion)))
            ;;    ("RedMetalCup" ,(tf:make-pose-stamped
            ;;                     "map" 0.0
            ;;                     (tf:make-3d-vector -1.55 -1.05 0.73)
            ;;                     (tf:euler->quaternion))))
            ;;  "iai_kitchen_sink_area_counter_top")
            (make-fixed-tabletop-goal
             `(("RedMetalPlate" ,(tf:make-pose-stamped
                                  "map" 0.0
                                  (tf:make-3d-vector -0.75 -0.90 0.75)
                                  (tf:euler->quaternion)))
               ("RedMetalCup" ,(tf:make-pose-stamped
                                "map" 0.0
                                (tf:make-3d-vector -0.95 -1.05 0.73)
                                (tf:euler->quaternion))))
             "iai_kitchen_sink_area_counter_top")
            ))
         (the-plan (plan (make-empty-state) goal)))
    (spawn-goal-objects goal target-table)
    (roslisp:ros-info (ltfnp) "The plan has ~a step(s)"
                      (length the-plan))
    (dolist (action the-plan)
      (destructuring-bind (type &rest rest) action
        (ecase type
          (:fetch
           (catch-all "fetch"
             (destructuring-bind (object) rest
               (with-designators ((fetch-action :action
                                                `((:to :fetch)
                                                  (:obj ,object))))
                 (perform fetch-action)))))
          (:place
           (catch-all "place"
             (destructuring-bind (object location) rest
               (with-designators ((place-action :action
                                                `((:to :place)
                                                  (:obj ,object)
                                                  (:at ,location))))
                 (go-to-origin :keep-orientation t)
                 (perform place-action))))))))))

(defun open-dishwasher ()
  (let ((model "IAI_kitchen")
        (link "sink_area_dish_washer_door_handle")
        (joint "sink_area_dish_washer_door_joint"))
    (move-to-relative-position
     (tf:make-pose-stamped
      "map" 0.0
      (tf:make-3d-vector 0.5 0.0 0.0)
      (tf:euler->quaternion))
     (tf:make-identity-pose))
    (pr2-manip-pm::execute-move-arm-poses
     :left `(,(tf:make-pose-stamped
               "torso_lift_link" 0.0
               (tf:make-3d-vector 0.45 0.0 -0.05)
               (tf:euler->quaternion :ax (/ pi 2))))
     (mot-man:make-goal-specification :moveit-goal-specification))
    (pr2-manip-pm::open-gripper :left)
    (pr2-manip-pm::execute-move-arm-poses
     :left `(,(tf:make-pose-stamped
               "torso_lift_link" 0.0
               (tf:make-3d-vector 0.58 0.0 -0.05)
               (tf:euler->quaternion :ax (/ pi 2))))
     (mot-man:make-goal-specification
      :moveit-goal-specification))
    (pr2-manip-pm::close-gripper :left)
    (sleep 3)
    (set-joint-limits model joint 0 1.57)
    ;;;(attach-to-joint-object "PR2" "l_wrist_roll_link" model link
    ;;;joint 0.0 1.57)
    
    ;; The gripper should now be wrapped around the handle enough in
    ;; order to pull it open. No need to fixate a joint between them,
    ;; as that will make non-radial movement of the gripper
    ;; impossible.
    
    ;;;---
    ;; TODO: Here, a sequence of opening-motions should be executed,
    ;; similar to how the fridge was opened. 3-4 segments should be
    ;; enough.
    ;;;---
    
    (fixate-joint model joint)
    (pr2-manip-pm::open-gripper :left)
    ;; NOTE/TODO: Actually, its probably better to stand besides the
    ;; dish washer and just pull the door open and let it smash to the
    ;; ground. Everything else is too much of a hassle, takes too
    ;; long, and will probably break a fraction of the simulation
    ;; attempts.
    ))

(defun get-semantic-object (name)
  (first (cram-semantic-map-designators:designator->semantic-map-objects
          (make-designator :object `((:name ,name))))))

(defun get-handle-strategy (handle)
  (cond ((or (string= handle "iai_kitchen_sink_area_left_upper_drawer_handle")
             (string= handle "iai_kitchen_sink_area_left_middle_drawer_handle")
             (string= handle "iai_kitchen_kitchen_island_left_upper_drawer_handle"))
         :linear-pull)
        ((or (string= handle "iai_kitchen_sink_area_dish_washer_door_handle")
             (string= handle "iai_kitchen_fridge_door_handle"))
         :revolute-pull)))

(defun get-handle-base-pose (handle &key (frame "map"))
  (let ((handle-object (get-semantic-object handle)))
    (ensure-pose-stamped
     (cram-semantic-map-utils:pose handle-object)
     :frame frame)))

(defun get-handle-axis (handle)
  (cond ((or (string= handle "iai_kitchen_sink_area_left_upper_drawer_handle")
             (string= handle "iai_kitchen_sink_area_left_middle_drawer_handle"))
         (tf:make-3d-vector -1 0 0))
        ((or (string= handle "iai_kitchen_kitchen_island_left_upper_drawer_handle"))
         (tf:make-3d-vector 1 0 0))
        ((or (string= handle "iai_kitchen_sink_area_dish_washer_door_handle"))
         (tf:make-3d-vector 0 -1 0))
        ((or (string= handle "iai_kitchen_fridge_door_handle"))
         (tf:make-3d-vector 0 0 1))))

(defun get-global-handle-axis (handle &key (frame "map"))
  (let* ((axis (get-handle-axis handle))
         (global-pose (get-handle-base-pose handle :frame frame))
         (transformed-axis-pose
           (cl-transforms:transform-pose
            (tf:make-transform (tf:make-identity-vector)
                               (tf:orientation global-pose))
            (tf:make-pose axis (tf:make-identity-rotation)))))
    (tf:origin transformed-axis-pose)))

(defmethod handle-motion-function (handle (strategy (eql :linear-pull)) &key (limits `(0 0.4)) (offset (tf:make-identity-pose)))
  (let* ((base-handle-pose (get-handle-base-pose handle))
         (transformed-handle-pose
           (tf:pose->pose-stamped
            (tf:frame-id base-handle-pose)
            (tf:stamp base-handle-pose)
            (cl-transforms:transform-pose
             (tf:pose->transform base-handle-pose)
             offset)))
         (axis (get-global-handle-axis handle))
         (motion-func
           (lambda (degree)
             (destructuring-bind (lower upper) limits
               (let ((normalized-degree
                       (+ lower (* degree (- upper lower)))))
                 (tf:pose->pose-stamped
                  (tf:frame-id transformed-handle-pose)
                  (tf:stamp transformed-handle-pose)
                  (cl-transforms:transform-pose
                   (tf:make-transform
                    (tf:v* axis normalized-degree)
                    (tf:make-identity-rotation))
                   transformed-handle-pose)))))))
    motion-func))

(defmethod handle-motion-function (handle (strategy (eql :revolute-pull)) &key (limits `(0 ,(/ pi 2))) (offset (tf:make-identity-pose)))
  )

(defun trace-handle-trajectory (handle trace-func &key (limits `(0 1) limitsp) (from-degree 0.0) (to-degree 1.0) (step 0.1) (offset (tf:make-identity-pose)))
  (let* ((strategy (get-handle-strategy handle))
         (motion-function
           (cond (limitsp (handle-motion-function
                           handle strategy :limits limits :offset offset))
                 (t (handle-motion-function handle strategy :offset offset))))
         (steps (/ (- to-degree from-degree) step)))
    (loop for i from 0 to steps
          as current-degree = (+ from-degree (* i step))
          as current-pose = (funcall motion-function current-degree)
          collect (funcall trace-func i current-pose))))

(defun show-handle-trajectory (handle &key (offset (tf:make-identity-pose)))
  (let* ((trace-func
           (lambda (step pose-stamped)
             (declare (ignore step))
             pose-stamped))
         (trace (trace-handle-trajectory handle trace-func :offset offset))
         (markers
           (roslisp:make-msg
            "visualization_msgs/MarkerArray"
            markers
            (map 'vector #'identity
                 (loop for i from 0 below (length trace)
                       as dot-msg = (roslisp:make-msg
                                     "visualization_msgs/Marker"
                                     (frame_id header) "map"
                                     pose (tf:to-msg (tf:pose-stamped->pose
                                                      (nth i trace)))
                                     ns "trace"
                                     id i
                                     type 2
                                     action 0
                                     (x scale) 0.03
                                     (y scale) 0.03
                                     (z scale) 0.03
                                     (r color) (- 1.0 (/ i (length trace)))
                                     (g color) (/ i (length trace))
                                     (b color) 0
                                     (a color) 1)
                       collect dot-msg)))))
    (roslisp:publish
     (roslisp:advertise "/handletrace" "visualization_msgs/MarkerArray")
     markers)))

(defun get-pose-difference (p-base p-ext &key (frame "map"))
  (let ((p-base (ensure-pose-stamped p-base :frame frame))
        (p-ext (ensure-pose-stamped p-ext :frame frame)))
    (tf:make-pose
     (tf:v- (tf:origin p-ext) (tf:origin p-base))
     (tf:orientation p-ext))))

(defun get-hand-handle-difference (arm handle)
  (let* ((handle-pose (get-handle-base-pose handle))
         (wrist-link (ecase arm
                       (:left "l_wrist_roll_link")
                       (:right "r_wrist_roll_link")))
         (pose-diff (get-pose-difference
                     handle-pose
                     (tf:pose->pose-stamped
                      wrist-link 0.0
                      (tf:make-identity-pose)))))
    pose-diff))

(defun move-base-relative (pose)
  (let* ((current-pose (ensure-pose-stamped (get-robot-pose)))
         (transformed-pose
           (tf:pose->pose-stamped
            (tf:frame-id current-pose)
            (tf:stamp current-pose)
            (cl-transforms:transform-pose
             (tf:pose->transform current-pose)
             pose))))
    (at-definite-location
     (make-designator
      :location `((:pose ,transformed-pose))))))

(defun execute-handle-trace (arm handle &key (from-degree 0.0) (to-degree 1.0) (step 0.1))
  (let* ((close-x 0.55)
         (trace-func
           (lambda (step pose-stamped)
             (declare (ignore step))
             (let ((in-tll (ensure-pose-stamped
                            pose-stamped
                            :frame "torso_lift_link")))
               (cond ((>= (tf:x (tf:origin in-tll)) close-x)
                      (move-arm-pose arm in-tll))
                     (t (let ((current-hand-in-tll
                                (ensure-pose-stamped
                                 (tf:pose->pose-stamped
                                  (ecase arm
                                    (:left "l_wrist_roll_link")
                                    (:right "r_wrist_roll_link"))
                                  0.0
                                  (tf:make-identity-pose))
                                 :frame "torso_lift_link")))
                          (when (>= (tf:x (tf:origin current-hand-in-tll)) close-x)
                            (move-arm-pose
                             arm
                             (tf:make-pose-stamped
                              (tf:frame-id in-tll)
                              (tf:stamp in-tll)
                              (tf:make-3d-vector
                               (+ (tf:x (tf:origin in-tll))
                                  (- (tf:x (tf:origin in-tll)) close-x))
                               (tf:y (tf:origin in-tll))
                               (tf:z (tf:origin in-tll)))
                              (tf:orientation in-tll))))
                          (move-base-relative
                           (tf:make-pose
                            (tf:make-3d-vector
                             (- (tf:x (tf:origin in-tll)) close-x) 0 0)
                            (tf:make-identity-rotation)))))))))
         (hand-diff (get-hand-handle-difference arm handle)))
    (trace-handle-trajectory
     handle trace-func
     :from-degree from-degree
     :to-degree to-degree
     :offset hand-diff
     :step step)))
