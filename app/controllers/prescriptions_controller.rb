class PrescriptionsController < ApplicationController
  def index
    @patient = Patient.find(params[:patient_id] || session[:patient_id]) rescue nil
    @orders = @patient.current_orders rescue []
    render :template => 'prescriptions/index', :layout => 'menu'
  end
  
  def new
    @patient = Patient.find(params[:patient_id] || session[:patient_id]) rescue nil
  end
  
  def void 
    @order = Order.find(params[:order_id])
    @order.void!
    flash.now[:notice] = "Order was successfully voided"
    index and return
  end
  
  def create
    @formulation = (params[:formulation] || '').upcase
    @drug = Drug.find_by_name(@formulation) rescue nil
    render :text => "No matching drugs found for #{params[:formulation]}" and return unless @drug
  
    @patient = Patient.find(params[:patient_id] || session[:patient_id]) rescue nil
    @encounter = @patient.current_treatment_encounter
    ActiveRecord::Base.transaction do
      @order = @encounter.orders.create(
        :order_type_id => 1, 
        :concept_id => 1, 
        :orderer => User.current_user.user_id, 
        :patient_id => @patient.id)        
      @drug_order = DrugOrder.new(
        :drug_inventory_id => @drug.id,
        :quantity => params[:quantity],
        :frequency => "morning: #{params[:morning_dose]}; " +
                      "afternoon: #{params[:afternoon_dose]}; " +
                      "evening: #{params[:evening_dose]}; " +
                      "night: #{params[:night_dose]}; ")
      @drug_order.order_id = @order.id                
      @drug_order.save!
    end                  
    redirect_to "/prescriptions?patient_id=#{@patient.id}"
  end
  
  # Look up the set of matching generic drugs based on the concepts. We 
  # limit the list to only the list of drugs that are actually in the 
  # drug list so we don't pick something we don't have.
  def generics
    search_string = (params[:search_string] || '').upcase
    filter_list = params[:filter_list].split(/, */) rescue []    
    @drug_concepts = Concept.active.find(:all, 
      :select => "concept_name.name", 
      :include => [:name], 
      :joins => "INNER JOIN drug ON drug.concept_id = concept.concept_id AND drug.retired = 0", 
      :conditions => ["concept_name.name LIKE ?", '%' + search_string + '%'])
    render :text => "<li>" + @drug_concepts.map{|drug_concept| drug_concept.name.name }.join("</li><li>") + "</li>"
  end
  
  # Look up all of the matching drugs for the given generic drugs
  def formulations
    @generic = (params[:generic] || '')
    @concept_ids = ConceptName.find_all_by_name(@generic).map{|c| c.concept_id}
    render :text => "" and return if @concept_ids.blank?
    search_string = (params[:search_string] || '').upcase
    @drugs = Drug.active.find(:all, 
      :select => "name", 
      :conditions => ["concept_id IN (?) AND name LIKE ?", @concept_ids, '%' + search_string + '%'])
    render :text => "<li>" + @drugs.map{|drug| drug.name }.join("</li><li>") + "</li>"
  end
  
  # Look up allowable frequency for the specific drug
  def frequencies
    @generic = (params[:generic] || '').upcase
    @concept_ids = ConceptName.find_all_by_name(@generic).map{|c| c.concept_id}
    render :text => "No matching generics found for #{params[:generic]}" and return if @concept_ids.blank?

    @formulation = (params[:formulation] || '').upcase
    drug = Drug.find_by_name(@formulation) rescue nil
    render :text => "No matching drugs found for #{params[:formulation]}" and return unless drug

    # Eventually we will have a real dosage table lookup here based on weight
    dosage_form = drug.form.name rescue 'dose'
    doses = [
      "None", 
      "1 #{dosage_form}", 
      "2 #{dosage_form.pluralize}", 
      "3 #{dosage_form.pluralize}", 
      "1/4 #{dosage_form}", 
      "1/3 #{dosage_form}", 
      "1/2 #{dosage_form}", 
      "3/4 #{dosage_form}", 
      "1 1/4 #{dosage_form}", 
      "1 1/2 #{dosage_form}", 
      "1 3/4 #{dosage_form}"]
    render :text => "<li>" + doses.join("</li><li>") + "</li>"
  end

  # Look up likely quantities for the drug
  def quantities
    @generic = (params[:generic] || '').upcase
    @concept_ids = ConceptName.find_all_by_name(@generic).map{|c| c.concept_id}
    render :text => "No matching generics found for #{params[:generic]}" and return if @concept_ids.blank?

    @formulation = (params[:formulation] || '').upcase
    drug = Drug.find_by_name(@formulation) rescue nil
    render :text => "No matching drugs found for #{params[:formulation]}" and return unless drug

    # Grab the 10 most popular quantities for this drug
    amounts = []
    orders = DrugOrder.find(:all, :limit => 10, :group => 'drug_inventory_id, quantity', :order => 'count(*)', :conditions => {:drug_inventory_id => drug.id})
    orders.each {|order|
      amounts << "#{order.quantity}"
    }  
    amounts << drug.pack_sizes
    amounts.flatten.compact.uniq
    render :text => "<li>" + amounts.join("</li><li>") + "</li>"
  end
  
end