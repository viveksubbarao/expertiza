class ParticipantsController < ApplicationController
  autocomplete :user, :name

  def action_allowed?
    if params[:action] == 'change_handle' or params[:action] == 'update_duties'
      ['Instructor',
       'Teaching Assistant',
       'Administrator',
       'Super-Administrator',
       'Student'].include? current_role_name
    else
      ['Instructor',
       'Teaching Assistant',
       'Administrator',
       'Super-Administrator'].include? current_role_name
    end
  end

  def list
    @root_node = Object.const_get(params[:model] + "Node").find_by_node_object_id(params[:id])
    @parent = Object.const_get(params[:model]).find(params[:id])
    @participants = @parent.participants
    @model = params[:model]
    # E726 Fall2012 Changes Begin
    @authorization = params[:authorization]
    # E726 Fall2012 Changes End
  end

  #OSS_808 change 28th oct
  #required for sending emails
  def email_sent
    DelayedMailer::deliver_mail("recipient.address@example.com")
  end

  def add
    curr_object = Object.const_get(params[:model]).find(params[:id])
    begin
      permissions = Participant.get_permissions(params[:authorization])
      curr_object.add_participant(params[:user][:name], permissions[:can_submit], permissions[:can_review], permissions[:can_take_quiz])
      user = User.find_by_name(params[:user][:name])
      @participant = curr_object.participants.find_by_user_id(user.id)
      undo_link("user \"#{params[:user][:name]}\" has successfully been added.")
    rescue
      flash[:error] = "User #{params[:user][:name]} does not exist or has already been added.</a>"
    end
    redirect_to :action => 'list', :id => curr_object.id, :model => params[:model], :authorization => params[:authorization]
  end

  def update_authorizations
    permissions = Participant.get_permissions(params[:authorization])
    participant = Participant.find(params[:id])
    parent_id = participant.parent_id
    participant.update_attributes(:can_submit => permissions[:can_submit], :can_review => permissions[:can_review], :can_take_quiz => permissions[:can_take_quiz])

    redirect_to :action => 'list', :id => parent_id, :model => participant.class.to_s.gsub("Participant", "")
  end

  #duties: manager, designer, programmer, tester
  def update_duties
    participant = Participant.find(params[:student_id])
    participant.update_attributes(:duty => params[:duty])
    redirect_to :controller => 'student_teams', :action => 'view', :student_id => participant.id
  end

  def destroy
    participant = Participant.find(params[:id])
    name = participant.user.name
    parent_id = participant.parent_id
    begin
      @participant = participant
      participant.delete(params[:force])
      flash[:note] = undo_link("User \"#{name}\" has been removed as a participant successfully. ")
    rescue => error
      url_yes = url_for :action => 'delete', :id => params[:id], :force => 1
      url_show = url_for :action => 'delete_display', :id => params[:id], :model => participant.class.to_s.gsub("Participant", "")
      url_no = url_for :action => 'list', :id => parent_id, :model => participant.class.to_s.gsub("Participant", "")
      flash[:error] = "A delete action failed: At least one (1) review mapping or team membership exist for this participant. <br/><a href='#{url_yes}'>Delete this participant</a>&nbsp;|&nbsp;<a href='#{url_show}'>Show me the associated items</a>|&nbsp;<a href='#{url_no}'>Do nothing</a><BR/>"
    end
    redirect_to :action => 'list', :id => parent_id, :model => participant.class.to_s.gsub("Participant", "")
  end

  def delete_display
    @participant = Participant.find(params[:id])
    @model = params[:model]
  end

  def delete_items
    participant = Participant.find(params[:id])
    maps = params[:ResponseMap]
    teamsusers = params[:TeamsUser]

    if !maps.nil?
      maps.each { |rmap_id|
        begin
          ResponseMap.find(rmap_id[0].to_i).delete(true)
        rescue
        end
      }
    end

    if !teamsusers.nil?
      teamsusers.each { |tuser_id|
        begin
          TeamsUser.find(tuser_id[0].to_i).delete
        rescue
        end
      }
    end

    redirect_to :action => 'delete', :id => participant.id, :method => :post
  end

  # Copies existing participants from a course down to an assignment
  def inherit
    assignment = Assignment.find(params[:id])

    if assignment.course
      if assignment.course.participants.length > 0
        @copied_participants = populate_copied_participants(assignment.courses.participants, params[:id])
        if @copied_participants.length > 0
          undo_link("Participants from \"#{course.name}\" have been copied to this assignment successfully. ")
        else
          flash[:note] = 'All course participants are already in this assignment'
        end
      else
        flash[:note] = "No participants were found to inherit."
      end
    else
      flash[:error] = "No course was found for this assignment."
    end

    redirect_to :controller => 'participants', :action => 'list', :id => assignment.id, :model => 'Assignment'
  end


  def bequeath_all
    assignment = Assignment.find(params[:id])

    if assignment.course
      @copied_participants = populate_copied_participants(assignment.participants, assignment.course.id)
      if @copied_participants.length > 0
        undo_link("All participants were successfully copied to \"#{course.name}\". ")
      else
        flash[:note] = 'All assignment participants are already part of the course'
      end
    else
      flash[:error] = "This assignment is not associated with a course."
    end

    redirect_to :controller => 'participants', :action => 'list', :id => assignment.id, :model => 'Assignment'
  end

  # Allow participant to change handle for this assignment
  # If the participant parameters are available, update the participant
  # and redirect to the view_actions page
  def change_handle
    @participant = AssignmentParticipant.find(params[:id])
    return unless current_user_id?(@participant.user_id)

    if params[:participant] != nil
      if AssignmentParticipant.where(parent_id: @participant.parent_id, handle: params[:participant][:handle]).length > 0
        flash[:error] = "<b>#{params[:participant][:handle]}</b> is already in use for this assignment. Please select a different handle."
        redirect_to :controller => 'participants', :action => 'change_handle', :id => @participant
      else
        @participant.update_attributes(participant_params)
        redirect_to :controller => 'student_task', :action => 'view', :id => @participant
      end
    end
  end

  def delete_assignment_participant
    contributor = AssignmentParticipant.find(params[:id])
    name = contributor.name
    assignment_id = contributor.assignment
    begin
      contributor.destroy
      flash[:note] = "\"#{name}\" is no longer a participant in this assignment."
    rescue
      flash[:error] = "\"#{name}\" was not removed. Please ensure that \"#{name}\" is not a reviewer or metareviewer and try again."
    end
    redirect_to :controller => 'review_mapping', :action => 'list_mappings', :id => assignment_id
  end

  private

  def participant_params
    params.require(:participant).permit(:can_submit, :can_review, :user_id, :parent_id, :directory_num, :submitted_at, :permission_granted, :penalty_accumulated, :submitted_hypelinks, :grade, :type, :handle, :time_stamp, :digital_signature, :duty, :can_take_quiz)
  end

  private

  def populate_copied_participants(participants, val)
    @copied_participants = []

    participants.each do |participant|
      new_participant = participant.copy(val)
      if new_participant
        @copied_participants.push new_participant
      end
    end

    return @copied_participants
  end
end
